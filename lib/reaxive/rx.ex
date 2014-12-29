defmodule Reaxive.Rx do

	require Logger
	alias Reaxive.Sync

	@moduledoc """
	This module implements the combinator on reactive streams of events.

	The functionality is closely modelled after Reactive Extensions and after ELM.
	However, names of function follow the tradition of Elixir's `Enum` and
	`Stream` modules, if applicable.

	See the test cases in `rx_test.exs` for usage patterns.
	"""

	# The Rx implementation expect generally to be disposed properly after
	# usage. Using auto_stop too aggressively is risky, because every event sent to
	# the Rx which is not properly subscribed might stop the Rx prematurely. Too bad!
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
	def eval(%Lazy{expr: exp} = e) do
		# Logger.info "Evaluating #{inspect e}"
		exp.()
	end
	def eval(exp), do: exp

	defimpl Observable, for: Reaxive.Rx.Lazy do
		def subscribe(observable, observer) do
			rx = Reaxive.Rx.eval(observable)
			# Logger.info "Evaluated #{inspect observable} to #{inspect rx}"
 			Observable.subscribe(rx, observer)
		end
	end

	#######################################################################################
	#######################################################################################

	@doc """
	This is a simple sink for events, which can be used for debugging
	event streams.
	"""
	@spec as_text(Observable.t) :: Observable.t
	def as_text(rx), do: rx |> map(fn(v) -> IO.inspect v end)

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
		lazy do
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
	end

	@spec update_buffer(%{pos_integer => term}, pos_integer, term) :: %{}
	defp update_buffer(buffer = %{}, index, value) do
		Dict.update(buffer, index, fn(old) -> [value | old] end)
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
		{:ok, rx} = Reaxive.Rx.Impl.start(id, @rx_defaults)
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
	The `distinct` transformation is a filter, which only passes values that it
	has not seen before. Since all distinct values has to be stores inside
	the filter, its required memory can grow for ever, if an unbounded #
	sequewnce is used.
	"""
	@spec distinct(Observer.t) :: Observer.t
	def distinct(rx) do
		{distinct_fun, acc} = Sync.distinct(HashSet.new())
		:ok = Reaxive.Rx.Impl.compose(rx, distinct_fun, acc)
		rx
	end

	@doc """
	The `distinct_until_changed` transformation is a filter, which filters
	out all repeating values, such that only value changes remain
	in the event sequence.
	"""
	@spec distinct_until_changed(Observer.t) :: Observer.t
	def distinct_until_changed(rx) do
		{distinct_fun, acc} = Sync.distinct_until_changed()
		:ok = Reaxive.Rx.Impl.compose(rx, distinct_fun, acc)
		rx
	end

	@spec drop(Observable.t, pos_integer) :: Observable.t
	def drop(rx, n) when n >= 0 do
		Reaxive.Rx.Impl.compose(rx, Sync.drop(n))
	end

	@doc """
	The `error` function takes an in Elixir defined exception and generate a stream with the
	exception as the only element. The stream starts after the first subscription.
	"""
	def error(%{__exception__: true} = exception, timeout \\ @rx_timeout) do
		delayed_start(fn(rx) ->
#			Logger.info("do on_error with #{inspect exception}")
			Observer.on_error(rx, exception) end, "error", timeout)
	end


	@doc """
	This function filter the event sequence such that only those
	events remain in the sequence for which `pred` returns true.

	In Reactive Extensions, this function is called `Where`.
	"""
	@spec filter(Observable.t, (any -> boolean)) :: Observable.t
	def filter(rx, pred) do
		{filter_fun, acc} = Sync.filter(pred)
		:ok = Reaxive.Rx.Impl.compose(rx, filter_fun, acc)
		rx
	end

	@doc """
	The first element of the event sequence. Does return the first scalar value
	and dispose the event sequence. The effect is similar to

		rx |> Rx.stream |> Stream.take(1) |> Enum.fetch(0)

	This function is not lazy, but evaluates eagerly and forces the subscription.
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
	The `generate` function takes a collection and generates for each
	element of the collection an event. The delay between the events
	is the second parameter. The delay also takes place before the
	very first event.

	This function is always a root in the net of communicating
	observables and does not depend on another observable.

	This function can also be used with a lazy stream, such that unfolds
	and the like generate infininte many values. A typical example is the
	natural number sequence or the tick sequence

		naturals = Rx.generate(Stream.unfold(0, fn(n) -> {n, n+1} end))
		ticks = Rx.generate(Stream.unfold(:tick, fn(x) -> {x, x} end))

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
	The `map` functions takes an observable `rx` and applies function `fun` to
	each of its values.

	In ELM, this function is called `lift`, since it lifts a pure function into
	a signal, i.e. into an observable.

	In Reactive Extensions, this function is called `Select`.
	"""
	@spec map(Observable.t, (... ->any) ) :: Observable.t
	def map(rx, fun) do
		{mapper, acc} = Sync.map(fun)
		:ok = Reaxive.Rx.Impl.compose(rx, mapper, acc)
		rx
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
		Reaxive.Rx.Impl.compose(rx, Sync.merge(n))
		# subscribe to all originating sequences ...
		disposes = rxs |> Enum.map &Observable.subscribe(&1, rx)
		# and set the new disposables as sources.
		:ok = Reaxive.Rx.Impl.source(rx, disposes)
		rx
	end

	@doc """
	Generates all naturals numbers starting with `0`.
	"""
	@spec naturals(pos_integer, pos_integer) :: Observable.t
	def naturals(delay \\ 50, timeout \\ @rx_timeout) do
		generate(Stream.unfold(0, fn(n) -> {n, n+1} end), delay, timeout)
	end

	@doc """
	The `never`function creates a stream of events that never pushes anything.
	"""
	@spec never() :: Observable.t
	def never() do
		lazy do
			{:ok, new_rx} = Reaxive.Rx.Impl.start("never", @rx_defaults)
			silence = fn(event, acc) -> {:ignore, event, acc} end
			:ok = Reaxive.Rx.Impl.fun(new_rx, silence)
			new_rx
		end
	end

	@doc """
	This function considers the past events to produce new events.
	Therefore this function is called in ELM `foldp`, folding over the past.

	In Elixir, it is the convention to call the fold function `reduce`, therefore
	we stick to this convention.

	This fold-function itself must follow the conventions of `Reaxive.Sync` module.
	"""
	@spec reduce(Observable.t, {Reaxive.Sync.reduce_fun_t, any}) :: Observable.t
	def reduce(rx, {reduce_fun, acc} = f) do
		:ok = Reaxive.Rx.Impl.compose(rx, f)
		rx
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
			source = Observable.subscribe(prev_rx, rx)
			:ok = Reaxive.Rx.Impl.source(rx, source)
		end, "start_with")
	end


	@doc """
	Converts a sequence of events into a (infinite) stream of events.

	This operator is not lazy, but eager, as it forces the subscribe and
	therefore the evaluation of the subscription.
	"""
	@spec stream(Observable.t) :: Enumerable.t
	def stream(rx) do
		# queue all events in an process and collect them.
		# the accumulator is the disposable, which does not change.
		o = stream_observer()
		Stream.resource(
			# initialize the stream: Connect with rx
			fn() -> Observable.subscribe(rx, o) end,
			# next element is taken from the message queue
			fn(acc) ->
				receive do
					{:on_next, value} -> {[value], acc}
					{:on_completed, nil} -> {:halt, acc}
					{:on_error, e} -> {:halt, {acc, e}} # should throw exception e!
				end
			end,
			# resource deallocation
			fn({rx2, e}) -> Disposable.dispose(rx2)
				 			e
			  (rx2) -> Disposable.dispose(rx2)

			end)
	end

	@doc "A simple observer function, sending tag and value as composed message to the process."
	def stream_observer(pid \\ self) do
		fn(tag, value) -> send(pid, {tag, value}) end
	end

	@doc "Sums up all events of the sequence and returns the sum as number"
	@spec sum(Observable.t) :: number
	def sum(rx) do
		{sum_fun, acc} = Sync.sum()
		:ok = Reaxive.Rx.Impl.compose(rx, sum_fun, acc)
		rx |> first
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
		{take_fun, acc} = Sync.take(n)
		:ok = Reaxive.Rx.Impl.compose(rx, take_fun, acc)
		rx
	end

	@doc """
	Takes the first elements of the sequence while the
	predicate is true.
	"""
	@spec take_while(Observable.t, (any -> boolean)) :: Observable.t
	def take_while(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.take_while(pred))
	end

	@doc """
	Takes the first elements of the sequence until the
	predicate is true.
	"""
	@spec take_until(Observable.t, (any -> boolean)) :: Observable.t
	def take_until(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.take_while(&(not pred.(&1))))
	end

	@doc false
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
