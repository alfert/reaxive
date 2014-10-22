defmodule Reaxive.Rx.Impl do

	use GenServer
	require Logger

	@moduledoc """
	Implements the Rx protocols and handles the contract. 
	"""

	@typedoc """
	Internal message for propagating events. 
	"""
	@type rx_propagate :: {:on_next, term} | {:on_error, term} | {:on_completed, nil}
	@typedoc """
	Tags for interacting between reduce-function and its reducers. They have the following 
	implications: 

	* `:cont`: continue with the iteration and send the current value to subscribers
	* `:ignore`: continue the iteration, but do not set anything to subscribers (i.e. ignore the value)
	* `:halt`: stop the iteration and send the current value to subscribers
	"""
	@type reduce_tag :: :cont | :halt | :ignore
	@typedoc "Return value of reducers"
	@type reducer :: {reduce_tag, rx_propagate, term}

	@type t :: %__MODULE__{}

	@derive Access
	defstruct id: nil, # might be handy to identify the Rx, but is it really required?
		active: true, # if false, then an error has occurred or the calculation is completed
		subscribers: [], # all interested observers
		sources: [], # list of disposables
		action: nil, # the function to be applied to the values
		options: [], #  behavior options
		on_subscribe: nil, # function called at first subscription 
		accu: nil # accumulator 

	@doc """
	Starts the Rx Impl. If `auto_stop` is true, the `Impl` finishes after completion or
	after an error or after unsubscribing the last subscriber.
	"""
	def start(), do: start(nil, [auto_stop: true])
	def start(id, options), do: 
		GenServer.start(__MODULE__, [id, options])
	
	def init([id, options]) do
		s = %__MODULE__{id: id, options: options}
		# Logger.info "init - state = #{inspect s}"
		{:ok, s}
	end
	
	# TODO:
	# Provide a function "connect" that is used to connect Rxs, similar as 
	# subscribe does now. But connect does not start any actions, this happens 
	# only after calling subscribe.

	@doc "Subscribes a new observer. Returns a function for unsubscription"
	@spec subscribe(Observable.t, Observer.t) :: (() -> :ok)
	def subscribe(observable, observer) do
		try do
			:ok = GenServer.call(observable, {:subscribe, observer})
		catch
			#########################
			##  Hier kann viel schief gehen, sobald der observable bereits fertig ist
			##  Dann schlagen die Aufrufe fehl, weil das Ziel nicht mehr da ist. 
			##  
			##  Diese Situation muss über den komplette Code hinweg 
			##  systematisch überprüft werden, da dies eine Race-Condition ist, 
			##  die immer mal wieder auftreten kann. 
			#########################

			:exit, {fail, {GenServer, :call, _}} when fail in [:normal, :noproc] -> 
				Logger.debug "subscribe failed because observable #{inspect observable} does not exist anymore"
				Logger.debug Exception.format_stacktrace()
				Observer.on_error(observer, :subscribe_failed)
				:ok
		end
		fn() -> 
			try do 
				unsubscribe(observable, observer) 
			catch 
				:exit, code -> Logger.debug "No process #{inspect observable} - no problem #{inspect code}"
			end
		end
	end
	
	@doc """
	Unsubscribes an `observer` from the event sequence.
	"""
	def unsubscribe(observable, observer), do:
		GenServer.call(observable, {:unsubscribe, observer})

	@doc """
	Sets the disposable event sequence `source`. This is needed for proper unsubscribing
	from the `source` when terminating the sequence.
	"""	
	def source(observable, disposable) do
		try do
			GenServer.call(observable, {:source, disposable})
		catch
			:exit, {fail, {GenServer, :call, _}} when fail in [:normal, :noproc] -> 
				Logger.debug "source failed because observable does not exist anymore"
				Disposable.dispose disposable
		end
	end

	@doc """
	This function sets the internal action on received events before the event is
	propagated to the subscribers. An initial accumulator value can also be provided.
	"""	
	def fun(observable, fun, acc \\ nil), do:	
		GenServer.call(observable, {:fun, fun, acc})

	@doc """
	Composes the internal action on received events with the given `fun`. The 
	initial function to compose with is the identity function.
	"""
	def compose(observable, fun), do:
		GenServer.call(observable, {:compose, fun})

	@doc "All subscribers of Rx. Useful for debugging."
	def subscribers(observable), do: GenServer.call(observable, :subscribers)

	@doc "Returns the accu value. Useful for debugging"
	def acc(observable), do: GenServer.call(observable, :accu)

	@doc "Sets the on_subscribe function, which is called for the first subscription."
	def on_subscribe(observable, on_subscribe), do: 
		GenServer.call(observable, {:on_subscribe, on_subscribe})

	@doc "All request-reply calls for setting up the Rx."
	def handle_call({:subscribe, observer}, _from, 
			%__MODULE__{subscribers: [], on_subscribe: nil} = state), do:
		do_subscribe(state, observer)
	def handle_call({:subscribe, observer}, _from, 
			%__MODULE__{subscribers: [], on_subscribe: on_subscribe} = state) do
		# If the on_subscribe hook is set, we call it on first subscription.
		# Introduced for properly implementing the Enum/Stream generator
		on_subscribe.()
		do_subscribe(state, observer)
	end
	def handle_call({:subscribe, observer}, _from, %__MODULE__{subscribers: sub} = state), do:
		do_subscribe(state, observer)
	def handle_call({:unsubscribe, observer}, _from, %__MODULE__{subscribers: sub} = state) do
		new_sub = List.delete(sub, observer)
		new_state = %__MODULE__{state | subscribers: new_sub}
		new_state = disconnect(new_state)
		case terminate?(new_state) do
			true  -> {:stop, :normal, new_state}
			false -> {:reply, :ok, new_state}
		end
	end
	def handle_call({:source, disposable}, _from, %__MODULE__{sources: []}= state) when is_list(disposable), do:
		{:reply, :ok, %__MODULE__{state | sources: disposable}}
	def handle_call({:source, disposable}, _from, %__MODULE__{sources: src}= state) when is_list(disposable), do:
		{:reply, :ok, %__MODULE__{state | sources: disposable ++ src}}
	def handle_call({:source, disposable}, _from, %__MODULE__{sources: src}= state), do:
		{:reply, :ok, %__MODULE__{state | sources: [disposable | src]}}
	def handle_call({:fun, fun, acc}, _from, %__MODULE__{action: nil}= state), do:
		{:reply, :ok, %__MODULE__{state | action: fun, accu: acc}}
	def handle_call({:compose, fun}, _from, %__MODULE__{action: nil}= state), do:
		{:reply, :ok, %__MODULE__{state | action: fun}}
	def handle_call({:compose, fun}, _from, %__MODULE__{action: g}= state), do:
		{:reply, :ok, %__MODULE__{state | action: fn(x) -> fun . (g . (x)) end}}
	def handle_call(:subscribers, _from, %__MODULE__{subscribers: sub} = s), do: {:reply, sub, s}
	def handle_call(:accu, _from, %__MODULE__{accu: acc} = s), do: {:reply, acc, s}
	def handle_call({:on_subscribe, fun}, _from, %__MODULE__{on_subscribe: nil}= state), do:
		{:reply, :ok, %__MODULE__{state | on_subscribe: fun}}

	@doc "Process the next value"
	def on_next(observer, value), do: 
		:ok = GenServer.cast(observer, {:on_next, value})

	@doc "The last regular message"
	def on_completed(observer), do:
		:ok = GenServer.cast(observer, {:on_completed, nil})

	@doc "An error has occured, the pipeline will be aborted."
	def on_error(observer, exception), do:
		:ok = GenServer.cast(observer, {:on_error, exception})

	@doc "Asynchronous callback. Used for processing values."
	def handle_cast({tag, v} = value, state) do
		# Logger.info "RxImpl #{inspect self} got message #{inspect value} in state #{inspect state}"
		new_state = handle_value(state, value)
		# checking for termination after every messages makes no sense. 
		# TODO: Check whether auto termination after on_error / on_complete is helpful
		# case terminate?(new_state) do
		# 	true  -> {:stop, :normal, new_state}
		# 	false -> {:noreply, new_state}
		# end
		{:noreply, new_state}
	end

	@doc """
	Internal function to handle new values, errors or completions. If `state.action` is 
	`:nil`, the value is propagated without any modification.
	"""
	def handle_value(%__MODULE__{active: true, action: nil} = state, {:on_completed, nil}) do
		notify({:cont, {:on_completed, nil}}, state)
		disconnect(state)
	end
	def handle_value(%__MODULE__{active: true, action: nil} = state, v) do #  = {:on_next, value}) do
		notify({:cont, v}, state)
		state
	end
	def handle_value(%__MODULE__{active: true, sources: src} = state, e = {:on_error, exception}) do
		notify({:cont, e}, state)
		disconnect(state)
	end
	def handle_value(%__MODULE__{active: true, action: fun, accu: accu} = state, value) do
		try do
			# Logger.debug "Handle_value with v=#{inspect value} and #{inspect state}"
			{tag, new_v, new_accu} = fun . (value, accu)
			:ok = notify({tag, new_v}, state)
			new_state = %__MODULE__{state | accu: new_accu}
			case tag do 
				:halt -> disconnect(new_state)
				_ -> new_state
			end
		catch 
			what, message -> 
				Logger.error "Got exception: #{inspect what}, #{inspect message} \n" <> 
					"with value #{inspect value} in state #{inspect state}\n" <>
					Exception.format(what, message)
				handle_value(state, {:on_error, {what, message}})
		end
	end 
	def handle_value(%__MODULE__{active: false} = state, _value), do: state

	@doc "Internal callback function at termination for clearing resources"
	def terminate(reason, state) do
		Logger.info("Terminating #{inspect self} for reason #{inspect reason} in state #{inspect state}")		
	end
			

	@doc "Internal function to disconnect from the sources"
	def disconnect(%__MODULE__{active: true, sources: src} = state) do
		src |> Enum.each &Disposable.dispose(&1) 
		%__MODULE__{state | active: false, subscribers: []}
	end
	# disconnecting from a disconnected state does not change anything
	def disconnect(%__MODULE__{active: false, subscribers: []} = state), do: state
	

	@doc "Internal function for subscribing a new `observer`"
	def do_subscribe(%__MODULE__{subscribers: sub}= state, observer) do
		# Logger.info "RxImpl #{inspect self} subscribes to #{inspect observer} in state #{inspect state}"
		{:reply, :ok, %__MODULE__{state | subscribers: [observer | sub]}}
	end

	@doc "Internal function to notify subscribers, knows about ignoring notifies."
	def notify({:ignore, _}, _), do: :ok
	def notify({:cont, {:on_next, value}}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_next(&1, value))
	def notify({:cont, {:on_error, exception}}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_error(&1, exception))
	def notify({:cont, {:on_completed, nil}}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_completed(&1))
	def notify({:halt, {:on_next, value}}, %__MODULE__{subscribers: subscribers}) do
		subscribers |> Enum.each(&Observer.on_next(&1, value))
		subscribers |> Enum.each(&Observer.on_completed(&1))
	end
	def notify({:halt, {:on_completed, nil}}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_completed(&1))
			

	@doc "Internal predicate to check if we terminate ourselves."
	def terminate?(%__MODULE__{options: options, subscribers: []}) do
		Keyword.get(options, :auto_stop, false)
	end
	def terminate?(%__MODULE__{options: options, active: false}) do
		Keyword.get(options, :auto_stop, false)
	end
	def terminate?(%__MODULE__{}), do: false
	

	defimpl Disposable, for: Function do
		def dispose(fun), do: fun.()
	end

	defimpl Observer, for: PID do
		def on_next(observer, value), do:      Reaxive.Rx.Impl.on_next(observer, value)
		def on_error(observer, exception), do: Reaxive.Rx.Impl.on_error(observer, exception)
		def on_completed(observer), do:        Reaxive.Rx.Impl.on_completed(observer)
	end

	defimpl Observable, for: PID do
		def subscribe(observable, observer), do: Reaxive.Rx.Impl.subscribe(observable, observer)
	end

	defimpl Observer, for: Function do
		def on_next(observer, value), do: observer.(:on_next, value)
		def on_error(observer, exception), do: observer.(:on_error, exception)
		def on_completed(observer), do: observer.(:on_completed, nil)
	end
end
