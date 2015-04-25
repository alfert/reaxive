defprotocol Observable do
	@moduledoc """
	Defines the subscribe function to subscribe to a calculation. The
	observer must follow the `Observer` protocol to be signalled about
	new values, errors and the completion of the calculation.
	"""
	@spec subscribe(Observable.t, Observer.t) :: {any, Disposable.t}
	def subscribe(observable, observer)
end

defprotocol Observer do
	@moduledoc """
	Defines the functions for providing a new value, to signal an error
	and to signal the completion of the observed calculation.

	Calls to the observer follow the regular sequence

		on_next* (on_error | on_completed)?

	It is the taks of `on_error` and `on_completed` to free up
	all internal resources. In particular the subscription needs
	to be closed. This can be done by calling `unsubscribe`.
	"""
	@spec on_next(Observer.t, any) :: :ok
	def on_next(observer, value)
	@spec on_error(Observer.t, any) :: :ok
	def on_error(observer, exception)
	@spec on_completed(Observer.t, Observable.t) :: :ok
	def on_completed(observer, observable)
end

defprotocol Subscription do
	@moduledoc """
	Defines the protocol for subscriptions providing a little
	bit more functionality as an `Disposable` from .NET-Framework. 
	"""
	
	@spec unsubscribe(Subscription.t) :: :ok
 	def unsubscribe(subscription)
 	@spec is_unsubscribed?(Subscription.t) :: boolean
 	def is_unsubscribed?(subscription)
 	
end

defprotocol Runnable do
	@moduledoc """
	Defines a protocol for starting a sequence of events. The basic idea
	is that only after calling `run` the sending of events starts, at least 
	for "cold" observables, which need to be started explicitely. 

	There are usually two basic modes of implementing `run`:

	* do some side effect for producing events, e.g. fork a new process sending 
	  events. This is the usual implementation for sources of an event sequence
	* in  an inbetween node, you will simply call `run` on your sources

	Some the `Rx` functions will call `run` to start immedietely the event sequence. 
	In particular functions like `to_list` or `stream` do it inside their implementation. 

	Where do we need an implementation of `Runnable`?

	* `Observables` need to implement `Runnable` such that we can start them from 
	   the outside on request.
	* The source connection between two `Observables` (i.e. `Rx_Impl` for now) needs
	  to contain a `Runnable` as firt component.

	"""

	@doc "Run start an event sequence. It returns its input parameters"
	@spec run(Runnable.t) :: Runnable.t
	def run(runnable)
end
