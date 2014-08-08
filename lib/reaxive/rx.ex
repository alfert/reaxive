defprotocol Observable do
	@moduledoc """
	Defines the subscribe function to subscribe to a calculation. The
	observer must follow the `Observer` protocol to be signalled about 
	new values, errors and the completion of the calculation.
	"""
	@spec subscribe(Observable.t, Observer.t) :: Disposable.t
	def subscribe(obserable, observer)
end

defprotocol Observer do
	@moduledoc """
	Defines the functions for providing a new value, to signal an error 
	and to signal the completion of the observed calculation.

	Calls to the observer follow the regular sequence 

		on_next* (on_error | on_completed)

	It is the taks of `on_error` and `on_completed` to free up 
	all internal resources. In particular the subscription needs
	to be closed. This can be done by calling `dispose`.
	"""
	@spec on_next(Observer.t, any) :: :ok
	def on_next(observer, value) 
	@spec on_error(Observer.t, any) :: :ok
	def on_error(observer, exception)
	@spec on_completed(Observer.t) :: :ok
	def on_completed(observer)
end

defprotocol Disposable do
	@moduledoc """
	Defines the function for canceling a running computation.
	"""
	def dispose(disposable)
end

defmodule Reaxive.Rx do
	
	@spec map(Observable.t, (... ->any) ) :: Observable.t
	def map(rx, fun) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		:ok = Reaxive.Rx.Impl.fun(new_rx, fun)
		new_rx
	end
	
	@spec generate(Enumerable.t, pos_integer) :: Observable.t
	def generate(collection, delay \\ 100) do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(rx, &(&1)) # identity fun
		send_values = fn() -> 
			receive do
				after delay -> :ok
			end
			collection |> Enum.each &Observer.on_next(rx, &1)
			Observer.on_completed(rx)
		end
		spawn(send_values)
		rx
	end
	
	# a simple sink
	@spec as_text(Observable.t) :: :none
	def as_text(rx) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		:ok = Reaxive.Rx.Impl.fun(new_rx, fn(v) -> IO.inspect v end)
		:none
	end
	
	def collect(rx) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		# TODO: Here we need the accumulator ....
		# :ok = Reaxive.Rx.Impl.fun(new_rx, fun)
		new_rx		
	end
	

end

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
		accu: nil # accumulator 

	def start(), do: Agent.start(fn() -> %__MODULE__{id: :erlang.make_ref()} end)
	
	def subscribe(observable, observer) do
		:ok = Agent.update(observable, fn(%__MODULE__{subscribers: sub}= state) -> 
			%__MODULE__{state | subscribers: [observer | sub]}
		end)
		fn() -> unsubscribe(observable, observer) end
	end
	
	def unsubscribe(observable, observer), do:
		Agent.update(observable, fn(%__MODULE__{subscribers: sub}= state) -> 
			%__MODULE__{state | subscribers: List.delete(sub, observer)}
		end)
	
	def source(observable, disposable), do:
		:ok = Agent.update(observable, fn(%__MODULE__{sources: src}= state) -> 
			%__MODULE__{state | sources: [disposable | src]}
		end)
	
	def fun(observable, fun), do:
		Agent.update(observable, fn(%__MODULE__{action: nil}= state) -> 
			%__MODULE__{state | action: fun}
		end)
	

	def on_next(observer, value) do
		:ok = Agent.cast(observer, &handle_value(&1, {:on_next, value}))
	end

	def on_completed(observer) do
		:ok = Agent.cast(observer, &handle_value(&1, :on_completed))
	end

	def on_error(observer, exception) do
		:ok = Agent.cast(observer, &handle_value(&1, {:on_error, exception}))
	end

	@doc "Internal function to handle new values, errors or completions"
	def handle_value(%__MODULE__{active: true} = state, {:on_next, value}) do
		try do 
			new_v = state.action . (value)
			state.subscribers |> Enum.each(&Observer.on_next(&1, new_v))
			state
		catch 
			what, message -> handle_value(state, {:on_error, {what, message}})
		end
	end
	def handle_value(%__MODULE__{active: true} = state, {:on_error, exception}) do
		state.subscribers |> Enum.each(&Observer.on_error(&1, exception))
		%__MODULE__{state | active: false}
	end
	def handle_value(%__MODULE__{active: true} = state, :on_completed) do
		state.subscribers |> Enum.each(&Observer.on_completed(&1))
		%__MODULE__{state | active: false}
	end

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
end
