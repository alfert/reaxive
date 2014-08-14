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
	def generate(collection, delay \\ 50)
	def generate(range = %Range{}, delay), do: generate(Enum.to_list(range), delay)
	def generate(collection, delay) do
		{:ok, rx} = Reaxive.Rx.Impl.start("generate")
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

	@doc """
	This function filter the event sequence such that only those
	events ŕemain in the sequence for which `pred` returns true. 

	In Reactive Extensions, this function is called `Where`. 
	"""
	@spec filter(Observable.t, (any -> boolean)) :: Observable.t
	def filter(rx, pred) do
		fun = fn(v) -> case (pred.(v)) do 
					true  -> {:cont, {:on_next, v}}
					false -> {:ignore, v}
				end
			end 
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(new_rx, fun, nil, :unwrapped)
		source = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, source)
		new_rx
	end
	

	@doc """
	This function considers the past events to produce new events. 
	Therefore this function is called in ELM `foldp`, folding over the past. 

	In Elixir, it is the convention to call the fold function `reduce`, therefore
	we stick to this convention.
	"""
	@spec reduce(Observable.t, any, ((any, Observable.t) -> Observable.t)) :: Observable.t
	def reduce(rx, acc, fun, wrapped \\ :wrapped) when is_function(fun, 2) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start("reduce")
		:ok = Reaxive.Rx.Impl.fun(new_rx, fun, acc, wrapped)
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		new_rx		
	end
	
	def take(rx, n) do
		stop = n
		fun = fn(v, 0) -> {:cont, {:on_completed, nil}, n}
		        (v, k) -> {:cont, {:on_next, v}, k-1} end
		reduce(rx, n, fun, :unwrapped)
	end

	@doc """
	The first element of the event sequence. Does return the first scalar value
	and dispose the event sequence. The effect is similar to 

		rx |> Rx.stream |> Stream.take(1) |> Enum.fetch(0)
	"""
	@spec first(Observable.t) :: Observable.t
	def first(rx) do 
		o = stream_observer(self)
		rx2 = Observable.subscribe(rx, o)
		val = receive do
			{:on_next, value} -> value
			{:on_completed, nil} -> nil
			{:on_error, e} -> raise e
		end
		Disposable.dispose(rx2)
		val
	end
end
