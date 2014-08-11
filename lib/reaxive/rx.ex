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

	*Important Remark:*

	The current implementation does not handle aborted calculations 
	properly but will crash.
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
	
	def collect(rx) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		# TODO: Here we need the accumulator ....
		# :ok = Reaxive.Rx.Impl.fun(new_rx, fun)
		new_rx		
	end
	

end
