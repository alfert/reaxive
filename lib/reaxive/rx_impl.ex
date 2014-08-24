defmodule Reaxive.Rx.Impl do

	use GenServer
	require Logger

	@moduledoc """
	Implements the Rx protocols and handles the contract. 

	Internally, we use the `Agent` module to ease the implementation.
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
		accu: nil # accumulator 

	@doc """
	Starts the Rx Impl. If `auto_stop` is true, the `Impl` finishes after completion or
	after an error or after unsubscribing the last subscriber.
	"""
	def start(id \\ nil, options \\ [auto_stop: true]), do: 
		GenServer.start(__MODULE__, [id, options])
	
	def init([id, options]) do
		{:ok, %__MODULE__{id: id, options: options}}
	end
	
	@doc "Subscribes a new observer. Returns a function for unsubscription"
	@spec subscribe(Observable.t, Observer.t) :: (() -> :ok)
	def subscribe(observable, observer) do
		:ok = GenServer.call(observable, {:subscribe, observer})
		fn() -> unsubscribe(observable, observer) end
	end
	
	def unsubscribe(observable, observer), do:
		GenServer.call(observable, {:unsubscribe, observer})
	
	def source(observable, disposable), do:
		GenServer.call(observable, {:source, disposable})
	@doc """
	This function sets the internal action of received events before the event is
	propagated to the subscribers. An initial accumulator value can also be provided.

	If the argument `wrap` is `:wrapped`, then the function is expected 
	to return directly the new value. If it is `:unwrapped`, then it is the task of the function 
	to return the complex value to signal propagation (`:cont`) or ignorance of events (`:ignore`).

		{:cont, {:on_next, value}} | {:ignore, value}

	"""	
	@spec fun(Observable.t, 
		(any -> any) | (any -> ({:cont, {:on_next, any}}|{:ignore, any})), 
		:wrapped | :unwrapped) :: :ok
	def fun(observable, fun, acc \\ nil, _wrap \\ :wrapped)
	
	def fun(observable, fun, acc, _wrap = :wrapped) when is_function(fun, 2), do:
		do_fun(observable, fn(v,accu) -> {value, new_accu} = fun.(v, accu)
			{:cont, {:on_next, value}, new_accu} end, acc)
	def fun(observable, fun, acc, _wrap = :unwrapped) when is_function(fun, 2), do:
		do_fun(observable, fun, acc)
	def fun(observable, fun, _acc = nil, _wrap = :wrapped) when is_function(fun, 1), do:
		do_fun(observable, fn(v, _acc) -> {:cont, {:on_next, fun.(v)}, _acc} end)
	def fun(observable, fun, _acc = nil, _wrap = :unwrapped), do:
		do_fun(observable, fn(v, acc) -> {tag, value} = fun.(v)
			{tag, value, acc} end)
	
	defp do_fun(observable, fun, acc \\ nil), do:	
		GenServer.call(observable, {:fun, fun, acc})

	@doc "All subscribers of Rx. Useful for debugging."
	def subscribers(observable), do: GenServer.call(observable, :subscribers)

	@doc "The accu value. Useful for debugging"
	def acc(observable), do: GenServer.call(observable, :accu)

	@doc "All request-reply calls for setting up the Rx."
	def handle_call({:subscribe, observer}, _from, %__MODULE__{subscribers: sub}= state), do:
		{:reply, :ok, %__MODULE__{state | subscribers: [observer | sub]}}
	def handle_call({:unsubscribe, observer}, _from, %__MODULE__{subscribers: sub}= state) do
		new_state = %__MODULE__{state | subscribers: List.delete(sub, observer)}
		case terminate?(new_state) do
			true  -> {:stop, :ok, new_state}
			false -> {:reply, :ok, new_state}
		end
	end
	def handle_call({:source, disposable}, _from, %__MODULE__{sources: src}= state), do:
		{:reply, :ok, %__MODULE__{state | sources: [disposable | src]}}
	def handle_call({:fun, fun, acc}, _from, %__MODULE__{action: nil}= state), do:
		{:reply, :ok, %__MODULE__{state | action: fun, accu: acc}}
	def handle_call(:subscribers, _from, %__MODULE__{subscribers: sub} = s), do: {:reply, sub, s}
	def handle_call(:accu, _from, %__MODULE__{accu: acc} = s), do: {:reply, acc, s}

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
		new_state = handle_value(state, value)
		case terminate?(new_state) do
			true  -> {:stop, :ok, new_state}
			false -> {:noreply, new_state}
		end
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
	def handle_value(%__MODULE__{active: false} = state, _value) do
		if terminate?(state), do:
			:ok = Agent.stop(self)
	end
	

	@doc "disconnect from the sources"
	def disconnect(%__MODULE__{active: true, sources: src} = state) do
		src |> Enum.each &Disposable.dispose(&1) 
		%__MODULE__{state | active: false, subscribers: []}
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
			

	@doc "Internal predication to check if we terminate ourselves."
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
