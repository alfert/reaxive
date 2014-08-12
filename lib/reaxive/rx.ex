defmodule Reaxive.Rx do
	
	@doc """
	The `map` functions takes an observable `rx` and applies function `fun` to 
	each of its values.

	In ELM, this function is called `lift`, since it lifts a pure function into 
	a signal, i.e. into an observable. 

	In Reactive Extensions, this function is called `Select`. 
	"""
	@spec map(Observable.t, (... ->any) ) :: Observable.t
	def map(rx, fun) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(new_rx, fun)
		source = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, source)
		new_rx
	end
	
	@doc """
	The `generate` function takes a collection and generates for each 
	element of the collection an event. The delay between the events 
	is the second parameter. The delay also takes place before the 
	very first event. 

	This function is always a root in the net of communicating
	observables and does not depend on another observable.

	*Important Remarks:*

	* The current implementation does not handle aborted calculations 
	  properly but will crash.
	* If the delay is set to too small value (e.g. `0`), then the first few
	  elements may be swalloed because no subscriber is available. This might
	  be changed in the future.
	"""
	@spec generate(Enumerable.t, pos_integer) :: Observable.t
	def generate(collection, delay \\ 50) do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(rx, &(&1)) # identity fun
		send_values = fn() -> 
			collection |> Enum.each(fn(element) -> 
				:timer.sleep(delay)
				Observer.on_next(rx, element)
			end) 
			Observer.on_completed(rx)
		end
		spawn(send_values)
		rx
	end
	
	@doc """
	This is a simple sink for events, which can be used for debugging
	event streams. 
	"""
	@spec as_text(Observable.t) :: Observable.t
	def as_text(rx), do: rx |> map(fn(v) -> IO.inspect v end)
	
	@doc """
	Converts a sequence of events into a (infinite) stream of events. 
	"""
	@spec stream(Observable.t) :: Enumerable.t
	def stream(rx) do
		# queue all events in an process and collect them.
		# the accumulator is the function, which gets the next 
		# element element from the enclosed process. 
		#
		o = stream_observer()
		Stream.resource(
			# initialize the stream: Connect with rx
			fn() -> Observable.subscribe(rx, o) end, 
			# next element is taken from the message queue
			fn(acc) -> 
				receive do
					{:on_next, value} -> {value, acc}
					{:on_completed, nil} -> nil
					{:on_error, _e} -> nil
				end
			end,
			# resource deallocation
			fn(rx2) -> Disposable.dispose(rx2) end)
	end
	
	@doc "A simple observer function, sending tag and value as composed message to the process."
	def stream_observer(pid \\ self) do
		fn(tag, value) -> send(pid, {tag, value}) end
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
