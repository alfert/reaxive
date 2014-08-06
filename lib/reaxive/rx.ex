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
	@moduledoc """
	Implements the Rx protocols and handles the contract. 

	Internally, we use the `Agent` module to ease the implementation.
	"""

	defstruct id: nil,
		subscribers: []

	def start(), do: Agent.start(fn() -> %__MODULE__{id: :erlang.make_ref()} end)
	
	def subscribe(observable, observer) do
		:ok = Agent.update(observable, fn(%__MODULE__{subscribers: sub}= state) -> 
			%__MODULE__{state | subscribers: [observer | sub]}
		end)
		fn() -> unsubscribe(observable, observer) end
	end
	
	def unsubscribe(observable, observer) do
		Agent.update(observable, fn(%__MODULE__{subscribers: sub}= state) -> 
			%__MODULE__{state | subscribers: List.delete(sub, observer)}
		end)
	end
	
	def subscribers(observable), do: 
		Agent.get(observable, fn(%__MODULE__{subscribers: sub}) -> sub end)

	defimpl Disposable, for: Function do
		def dispose(fun), do: fun.()
	end
	
end