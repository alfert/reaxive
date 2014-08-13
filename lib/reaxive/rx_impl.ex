defmodule Reaxive.Rx.Impl do
	@moduledoc """
	Implements the Rx protocols and handles the contract. 

	Internally, we use the `Agent` module to ease the implementation.
	"""

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
	def start(options \\ [auto_stop: true]), do: 
		Agent.start(fn() -> %__MODULE__{id: :erlang.make_ref(), options: options} end)
	
	def subscribe(observable, observer) do
		:ok = Agent.update(observable, fn(%__MODULE__{subscribers: sub}= state) -> 
			%__MODULE__{state | subscribers: [observer | sub]}
		end)
		fn() -> unsubscribe(observable, observer) end
	end
	
	def unsubscribe(observable, observer) do
		finish? = Agent.get_and_update(observable, fn(%__MODULE__{subscribers: sub}= state) -> 
			new_state = %__MODULE__{state | subscribers: List.delete(sub, observer)}
			{terminate?(new_state), new_state}
		end)
		if finish?, do: :ok = Agent.stop(observable), else: :ok
	end
	
	def source(observable, disposable), do:
		:ok = Agent.update(observable, fn(%__MODULE__{sources: src}= state) -> 
			%__MODULE__{state | sources: [disposable | src]}
		end)

	@doc """
	This function sets the internal action of received events before the event is
	propagated to the subscribers. 

	If the argument `wrap` is `:wrapped`, then the function is expected 
	to return directly the new value. If it is `:unwrapped`, then it is the task of the function 
	to return the complex value to signal propagation (`:cont`) or ignorance of events (`:ignore`).

		{:cont, {:on_next, value}} | {:ignore, value}

	"""	
	@spec fun(Observable.t, 
		(any -> any) | (any -> ({:cont, {:on_next, any}}|{:ignore, any})), 
		:wrapped | :unwrapped) :: :ok
	def fun(observable, fun, _wrap \\ :wrapped)
	def fun(observable, fun, _wrap = :wrapped), do:
		Agent.update(observable, fn(%__MODULE__{action: nil}= state) -> 
			%__MODULE__{state | action: fn(v) -> {:cont, {:on_next, fun.(v)}} end}
		end)
	def fun(observable, fun, _wrap = :unwrapped), do:
		Agent.update(observable, fn(%__MODULE__{action: nil}= state) -> 
			%__MODULE__{state | action: fun}
		end)

	def on_next(observer, value), do: 
		:ok = Agent.cast(observer, &handle_value(&1, {:on_next, value}))

	# Here we need to end the process. To synchronize behaviour, we need 
	# call the Agent. Is this really the sensible case or do we block outselves?
	def on_completed(observer), do:
		:ok = Agent.cast(observer, &handle_value(&1, :on_completed))

	def on_error(observer, exception), do:
		:ok = Agent.cast(observer, &handle_value(&1, {:on_error, exception}))

	@doc """
	Internal function to handle new values, errors or completions. If `state.action` is 
	`:nil`, the value is propagated without any modification.
	"""
	def handle_value(%__MODULE__{active: true, action: nil} = state, v = {:on_next, value}) do
		notify({:cont, v}, state)
		state
	end
	def handle_value(%__MODULE__{active: true} = state, {:on_next, value}) do
		try do 
			new_v = state.action . (value)
			notify(new_v, state)
			state
		catch 
			what, message -> handle_value(state, {:on_error, {what, message}})
		end
	end
	def handle_value(%__MODULE__{active: true} = state, e = {:on_error, exception}) do
		notify({:cont, e}, state)
		state.sources |> Enum.each &Disposable.dispose(&1) # disconnect from the sources
		%__MODULE__{state | active: false, subscribers: []}
	end
	def handle_value(%__MODULE__{active: true} = state, :on_completed) do
		notify({:cont, :on_completed}, state)
		state.sources |> Enum.each &Disposable.dispose(&1) # disconnect from the sources
		%__MODULE__{state | active: false, subscribers: []}
	end

	@doc "Internal function to notify subscribers, knows about ignoring notifies."
	def notify({:ignore, _}, _), do: :ok
	def notify({:cont, {:on_next, value}}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_next(&1, value))
	def notify({:cont, {:on_error, exception}}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_error(&1, exception))
	def notify({:cont, :on_completed}, %__MODULE__{subscribers: subscribers}), do: 
		subscribers |> Enum.each(&Observer.on_completed(&1))
			

	@doc "Internal predication to check if we terminate ourselves."
	def terminate?(%__MODULE__{options: options, subscribers: []}) do
		Keyword.get(options, :auto_stop, false)
	end
	def terminate?(%__MODULE__{options: options, active: false}) do
		Keyword.get(options, :auto_stop, false)
	end
	def terminate?(%__MODULE__{}), do: false
	

	def subscribers(observable), do: 
		Agent.get(observable, fn(%__MODULE__{subscribers: sub}) -> sub end)


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
