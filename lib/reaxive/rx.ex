defmodule Reaxive.Rx do

	@moduledoc """
	This module implements the combinator on reactive streams of events. 

	The functionality is closely modelled after Reactive Extensions and after ELM. 
	However, names of function follow the tradition of Elixir's `Enum` and 
	`Stream` modules, if applicable.

	See the test cases in `rx_test.exs` for usage patterns. 
	"""

	@rx_defaults [auto_stop: true]
	@rx_timeout 5_000
	
	defmodule Lazy do
		@moduledoc """
		Datastructure to encode a lazy thunk.
		"""
		defstruct expr: nil	
	end


	@doc """
	This macros suspends an expression and replaces is with an `Rx.Lazy` thunk.
	"""
	defmacro lazy([{:do, expr}]) do
		quote do
			%Lazy{expr: fn() -> unquote(expr) end}
		end
	end
	defmacro lazy(expr) do
		quote do
			%Lazy{expr: fn() -> unquote(expr) end}
		end
	end

	@doc """
	Evaluates a lazy expression, encoded in `Rx.Lazy`. Returns the argument
	if it is not an `Rx.Lazy` encoded 
	"""
	def eval(%Lazy{expr: exp}), do: exp.()
	def eval(exp), do: exp
	
	
	@doc """
	The `never`function creates a stream of events that never pushes anything. 
	"""
	@spec never() :: Observable.t
	def never() do
		{:ok, new_rx} = Reaxive.Rx.Impl.start("never", @rx_defaults)
		silence = fn(event, acc) -> {:ignore, event, acc} end
		:ok = Reaxive.Rx.Impl.fun(new_rx, silence)
		new_rx
	end

	@doc """
	The `error` function takes an in Elixir defined exception and generate a stream with the 
	exception as the only element. The stream starts after the first subscription. 
	"""
	def error(%{__exception__: true} = exception, timeout \\ @rx_timeout) do
		delayed_start(fn(rx) -> 
			Observer.on_error(rx, exception) end, "error", timeout)
	end
	
	@doc """
	The function `start_with` takes a stream of events `prev_rx` and a collection. 
	The resulting stream of events has all elements of the colletion, 
	followed by the events of `prev_rx`.
	"""
	@spec start_with(Observable.t, Enumerable.t) :: Observable.t
	def start_with(prev_rx, collection) do
		delayed_start(fn(rx) -> 
			for e <- collection, do: Observer.on_next(rx, e)
			source = Reaxive.Rx.Impl.subscribe(prev_rx, rx)
			:ok = Reaxive.Rx.Impl.source(rx, source)
		end, "start_with")
	end
	

	@doc """
	The `map` functions takes an observable `rx` and applies function `fun` to 
	each of its values.

	In ELM, this function is called `lift`, since it lifts a pure function into 
	a signal, i.e. into an observable. 

	In Reactive Extensions, this function is called `Select`. 
	"""
	@spec map(Observable.t, (... ->any) ) :: Observable.t
	def map(rx, fun) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start("map", @rx_defaults)

		mapper = fn
			({:on_next, v}, acc) -> {:cont, {:on_next, fun.(v)}, acc}
			({:on_completed, v}, acc) -> {:cont, {:on_completed, v}, acc}
		end
		:ok = Reaxive.Rx.Impl.fun(new_rx, mapper)
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
	@spec generate(Enumerable.t, pos_integer, pos_integer) :: Observable.t
	def generate(collection, delay \\ 50, timeout \\ @rx_timeout)
	def generate(collection, delay, timeout) do
		send_values = fn(rx) -> 
			collection |> Enum.each(fn(element) -> 
				:timer.sleep(delay)
				Observer.on_next(rx, element)
			end) 
			Observer.on_completed(rx)
		end	
		delayed_start(send_values, "generate", timeout)
	end

	@doc """
	The `delayed_start` function starts a generator after the first 
	subscription has arrived. The `generator` gets as argument `rx` the
	new creately `Rx_Impl` and sends is internally encoded values via 

		Observer.on_next(rx, some_value)

	All other functions on `Rx_Impl` and `Observer`, respectivley, can be called 
	within `generator` as well. 

	If within `timeout` milliseconds no subscriber has arrived, the 
	stream of events is stopped. This ensures that we get no memory leak. 
	"""
	@spec delayed_start(((Observer.t) -> any), String.t, pos_integer) :: Observable.t
	def delayed_start(generator, id \\ "delayed_start", timeout \\ @rx_timeout) do
		{:ok, rx} = Reaxive.Rx.Impl.start(id, [auto_stop: true])
		delayed = fn() -> 
			receive do
				:go -> generator.(rx)
			after timeout ->
				Observer.on_error(rx, :timeout)
			end
		end
		pid = spawn(delayed)
		Reaxive.Rx.Impl.on_subscribe(rx, fn()-> send(pid, :go) end)
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
					{:on_next, value} -> {[value], acc}
					{:on_completed, nil} -> {:halt, acc}
					{:on_error, _e} -> {:halt, acc}
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
		filter_fun = fn
			({:on_next, v}, acc) -> case pred.(v) do 
					true  -> {:cont, {:on_next, v}, acc}
					false -> {:ignore, v, acc}
				end
			({:on_completed, v}, acc) -> {:cont, {:on_completed, v}, acc}
		end
		
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(new_rx, filter_fun)
		source = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, source)
		new_rx
	end
	

	@doc """
	This function considers the past events to produce new events. 
	Therefore this function is called in ELM `foldp`, folding over the past. 

	In Elixir, it is the convention to call the fold function `reduce`, therefore
	we stick to this convention.

	This fold-function itself is somewhat complicated. 
	"""
	@spec reduce(Observable.t, any, ((any, Observable.t) -> Observable.t)) :: Observable.t
	def reduce(rx, acc, fun) when is_function(fun, 2) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start("reduce", @rx_defaults)
		:ok = Reaxive.Rx.Impl.fun(new_rx, fun, acc)
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		new_rx		
	end
	
	@doc """
	This function produces only the first `n` elements of the event sequence. 
	`n` must be positive. 

	A negative `n` would take elements from the back (the last `n` elements.) 
	This can be achieved by converting the sequence into a stream and back again: 

		rx |> Rx.stream |> Stream.take(-n) |> Rx.generate	
	"""
	@spec take(Observable.t, pos_integer) :: Observable.t
	def take(rx, n) when n >= 0 do
		fun = fn
			({:on_next, _v}, 0) -> {:cont, {:on_completed, nil}, n}
		    ({:on_next, v}, k) -> {:cont, {:on_next, v}, k-1} 
			({:on_completed, v}, acc) -> {:cont, {:on_completed, v}, acc}
		end
		reduce(rx, n, fun)
	end

	@doc """
	The first element of the event sequence. Does return the first scalar value
	and dispose the event sequence. The effect is similar to 

		rx |> Rx.stream |> Stream.take(1) |> Enum.fetch(0)
	"""
	@spec first(Observable.t) :: term
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

	@doc """
	Merges two or more event sequences in a non-deterministic order. 

	The result sequences finishes after all sequences have finished without errors 
	or immediately after the first error.
	"""
	@spec merge(Observable.t, Observable.t) :: Observable.t
	def merge(rx1, rx2), do: merge([rx1, rx2])
	@spec merge([Observable.t]) :: Observable.t
	def merge(rxs) when is_list(rxs) do
		{:ok, rx} = Reaxive.Rx.Impl.start("merge", @rx_defaults)

		# we need a reduce like function, that
		#  a) aborts immediately if an Exception occurs
		#  b) finishes only after all sources have finished
		n = length(rxs)
		fold_fun = fn
		    ({:on_next, v}, k) -> {:cont, {:on_next, v}, k} 
			({:on_completed, v}, 1) -> {:cont, {:on_completed, v}, 0}
			({:on_completed, v}, k) -> {:ignore, {:on_completed, v}, k-1}
		end
		Reaxive.Rx.Impl.fun(rx, fold_fun, n)
		# subscribe to all originating sequences ...
		disposes = rxs |> Enum.map &Observable.subscribe(&1, rx)
		# and set the new disposables as sources.
		:ok = Reaxive.Rx.Impl.source(rx, disposes)
		rx
	end
	
	@doc """
	Concatenates serveral event sequences. 

	Makes only sense, if the sequences are finite, because all events 
	from the later sequences need to buffered until the earlier 
	sequences finish. If any of the sequences produce an error, the concatenation 
	is aborted.

	This function cannot easily implemented here. 
	"""
	@spec concat([Observable.t]) :: Observable.t
	def concat(rxs) when is_list(rxs) do
		{:ok, rx} = Reaxive.Rx.Impl.start("concat", @rx_defaults)
		# we need a reduce like function, that
		#  a) aborts immediately if an Exception occurs
		#  b) finishes only after all sources have finished
		#  c) buffers all events that are coming from the current
		#     event sequence 
		# 
		n = length(rxs)
		# add to each rx a mapped rx which returns {number_of_rx, event} pairs
		indexed = rxs |> Enum.with_index |> 
			Enum.map (fn({rx, i}) -> map(rx, fn(v) -> {i, v} end) end)

		fold_fun = fn
			# a value of the current sequence is pushed out
		    ({:on_next, {i, v}}, {i, buffer}) -> {:cont, {:on_next, v}, {i, buffer}} 
		    # a value of a not current sequence is buffered
		    ({:on_next, {i, v}}, {k, buffer}) -> {:ignore, {:on_next, v}, {k, update_buffer(buffer, i, v)}} 
			# the final sequence is finished. Now finish the entíre sequence
			({:on_completed, {n, v}}, {i, buffer}) -> {:cont, {:on_completed, v}, {n, Dict.delete(buffer, i)}}
		    # the current sequence is finished. Take the next one, push all ot its buffered events out
		    # (in reverse order) and ignore the complete
			({:on_completed, {i, v}}, {i, buffer}) -> 
				# This won't work, since we need the state of Rx. Hmmmm.
				Reaxive.Rx.Impl.notify({:cont, {:on_next, v}, {i, buffer}} )
				{:ignore, {:on_completed, v}, {i + 1, Dict.delete(buffer, i)}}
			({:on_completed, {i, v}}, k) -> {:ignore, {:on_completed, v}, k-1}
		end

		Reaxive.Rx.Impl.fun(rx, fold_fun, n)
		# subscribe to all originating sequences ...
		disposes = rxs |> Enum.map &Observable.subscribe(&1, rx)
		# and set the new disposables as sources.
		:ok = Reaxive.Rx.Impl.source(rx, disposes)
		rx
	end
	
	@spec update_buffer(%{pos_integer => term}, pos_integer, term) :: %{}
	def update_buffer(buffer = %{}, index, value) do
		Dict.update(buffer, index, fn(old) -> [value | old] end)
	end

	def sum(rx) do
		fun = fn
			({:on_next, entry}, acc) -> {:ignore, nil, entry + acc} 
			({:on_completed, _}, acc) -> {:halt, {:on_next, acc}, acc}
		end

		rx |> reduce(0, fun) |> first
	end
	
	def accumulator(rx) do
		# This is not the proper solution. We need something, that is handled differently
		# in the handle_value implementation and sends the final value of the accu
		# after receiving the :on_completed message.

		# ==> It might be useful to consider the Enum-Protocol for reducers
		# to communicate between rx_impl nodes and the reducer functions. Interestingly, 
		# Enum has {:cont, term} and {:halt, term}, which might be useful here. If we change
		# from {:on_completed, nil} to {:on_completed, term}, we also have to change the 
		# Observer protocol!

		Reaxive.Rx.Impl.acc(rx)
	end
end
