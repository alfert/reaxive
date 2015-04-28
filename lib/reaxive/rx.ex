defmodule Reaxive.Rx do

	require Logger
	alias Reaxive.Sync
	alias Reaxive.Generator

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
	# The timeout for subscriptions is per default 5 seconds
	@rx_timeout 5_000
	# the delay between pushing events is per default 0 milli second
	@rx_delay 0

	@typedoc "The basic type of Rx is an `Observable`"
	@type t :: Observable.t

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
	def eval(%Lazy{expr: exp} = _e) do
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
	Returns `true` if `pred` holds for all events in the sequence.

	## Examples 

		iex> alias Reaxive.Rx
		iex> require Integer
		iex> Rx.naturals |> Rx.take(10) |> Rx.map(&(1+&1*2)) |> Rx.all &Integer.is_odd/1
		true
	"""
	@spec all(Observable.t, (any -> boolean)) :: boolean
	def all(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.all(pred)) |> first
	end

	@doc """
	Returns `true` if `pred` holds for at least one event in the sequence.

	## Examples 

		iex> alias Reaxive.Rx
		iex> require Integer
		iex> Rx.naturals |> Rx.take(10) |> Rx.any fn(x) -> x > 5 end
		true
	"""
	@spec any(Observable.t, (any -> boolean)) :: boolean
	def any(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.any(pred)) |> first
	end

	@doc """
	This is a simple sink for events, which can be used for debugging
	event streams. It writes all events to standard out.
	"""
	@spec as_text(Observable.t) :: Observable.t
	def as_text(rx) do
		rx |> Reaxive.Rx.Impl.compose(Sync.as_text)
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
	@spec delayed_start(((Observer.t) -> any), String.t, non_neg_integer) :: Observable.t
	def delayed_start(generator, id \\ "delayed_start", timeout \\ @rx_timeout) do
		{:ok, rx} = Reaxive.Rx.Impl.start(id, @rx_defaults)
		delayed = fn() ->
			receive do
				:go -> 
					# Logger.debug "Got :go"
					generator.(rx)
					# Logger.debug(":go got finished")
				:run -> 
					# Logger.debug "Got :run!"
					generator.(rx)
			after timeout ->
				Observer.on_error(rx, :timeout)
			end
		end
		pid = spawn(delayed)
		# Logger.debug ("spawned delayed start process #{inspect pid}")
		Reaxive.Rx.Impl.on_run(rx, fn()-> send(pid, :go) end)
		# create a subscription to properly cancel the generator
		{:ok, sub} = Reaxive.Subscription.start_link(
			fn() -> 
				# Logger.debug "Got an unsubscription, cancel process #{inspect pid}"
				send(pid, :cancel) 
				:ok
			end)
		# Logger.debug "delayed subscription is #{inspect sub}"
		# set the source, otherwise rx kills himslef due to a lacking source
		Reaxive.Rx.Impl.source(rx, {pid, sub})
		rx
	end


	@doc """
	The `distinct` transformation is a filter, which only passes values that it
	has not seen before. Since all distinct values has to be stored inside
	the filter, its required memory can grow for ever, if an unbounded 
	sequence is used.

	## Examples 

		iex> alias Reaxive.Rx 
		iex> [1, 1, 2, 1, 2, 2, 3, 1] |> Rx.generate |> Rx.distinct |> Rx.to_list
		[1, 2, 3]
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

	## Examples

		iex> alias Reaxive.Rx 
		iex> [1, 1, 2, 1, 2, 2, 3, 1] |> Rx.generate |> Rx.distinct_until_changed |> Rx.to_list
		[1, 2, 1, 2, 3,  1]
	"""
	@spec distinct_until_changed(Observer.t) :: Observer.t
	def distinct_until_changed(rx) do
		{distinct_fun, acc} = Sync.distinct_until_changed()
		:ok = Reaxive.Rx.Impl.compose(rx, distinct_fun, acc)
		rx
	end

	@doc """
	`drop` filters out the first `n` elements of the sequence.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take(10) |> Rx.drop(5) |> Rx.to_list
		[5, 6, 7, 8, 9]
	"""
	@spec drop(Observable.t, non_neg_integer) :: Observable.t
	def drop(rx, n) when n >= 0 do
		Reaxive.Rx.Impl.compose(rx, Sync.drop(n))
	end

	@doc """
	drop_while` filters out the first elements while the predicate is `true`.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take(10) |> Rx.drop_while(&(&1 < 5)) |> Rx.to_list
		[5, 6, 7, 8, 9]
	"""
	@spec drop_while(Observable.t, (any -> boolean)) :: Observable.t
	def drop_while(rx, pred) do
		Reaxive.Rx.Impl.compose(rx, Sync.drop_while(pred))
	end

	@doc """
	Creates the empty sequence of events. After a subscription, the
	sequence terminates immediately.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.empty |> Rx.stream |> Enum.to_list
		[]
	"""
	def empty(timeout \\ @rx_timeout) do
		delayed_start(fn(rx) ->
			Observer.on_completed(rx, rx) end, "empty", timeout)
		end

  @doc """
	The `error` function takes an in Elixir defined exception and generate a stream with the
	exception as the only element. 

	## Examples

		iex> alias Reaxive.Rx
		iex> me = self
		iex> Rx.error(RuntimeError.exception("yeah")) |> 
		iex> Observable.subscribe(fn(t, x) -> me |> send {t, x} end) |> Runnable.run
		iex> receive do x -> x end
		{:on_error, %RuntimeError{message: "yeah"}} 
	"""
	def error(%{__exception__: true} = exception, timeout \\ @rx_timeout) do
		delayed_start(fn(rx) ->
			# Logger.info("do on_error with #{inspect exception}")
			Observer.on_error(rx, exception) end, "error", timeout)
	end


	@doc """
	This function filter the event sequence such that only those
	events remain in the sequence for which `pred` returns true.

	In Reactive Extensions, this function is called `Where`.

	## Examples

		iex> alias Reaxive.Rx
		iex> require Integer
		iex> Rx.naturals |> Rx.take(5) |> Rx.filter(&Integer.is_even/1) |> Rx.to_list
		[0, 2, 4]
	"""
	@spec filter(Observable.t, (any -> boolean)) :: Observable.t
	def filter(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.filter(pred))
	end

	@doc """
	The first element of the event sequence. Does return the first scalar value
	and dispose the event sequence. The effect is similar to

		rx |> Rx.stream |> Stream.take(1) |> Enum.fetch(0)

	This function is not lazy, but evaluates eagerly and forces the subscription.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take(5) |> Rx.first
		0

		iex> alias Reaxive.Rx
		iex> Rx.return(3) |> Rx.first
		3
	"""
	@spec first(Observable.t) :: term
	def first(rx) do
		o = stream_observer(self)
		{_id, rx2} = Observable.subscribe(rx, o) |> Runnable.run()
		val = receive do
			{:on_next, value} -> value
			{:on_completed, _any} -> nil
			{:on_error, e} -> raise e
		end
		# Subscription.unsubscribe(rx2)
		Subscription.unsubscribe(rx2)
		val
	end

	@doc """
	The `flat_map` function takes a mapping function and a sequence
	of events. It applies the `map_fun` to each source event. The `map_fun` is a
	function which must return a sequence of events (i.e. an `Observable`). All
	resulting sequences are then flattened, such that only one sequence of events
	is returned from `flat_map`. Since all sequences generated by the mapping
	process are running concurrently to each other, the flattening process
	does not ensure any ordering of the resulting event sequence.

	In Reactive Extensions, this function is called `SelectMany`.
	"""
	@spec flat_map(Observable.t, (any -> Observable.t)) :: Observable.t
	def flat_map(rx, map_fun) do
		# `flatter` does not stop automatically if no source is available
		# because the mapper decides when there are no source anymore.
		{:ok, flatter} = Reaxive.Rx.Impl.start("flatter", [auto_stop: true])
		# Logger.info("created flatter #{inspect flatter}")

		rx |> Reaxive.Rx.Impl.compose(
			Sync.flat_mapper(
				flatter |> Reaxive.Rx.Impl.compose(Sync.flatter()),
				map_fun))
		disp_me = Observable.subscribe(rx, flatter)
		# Logger.debug("disp_me is #{inspect disp_me}")
		Reaxive.Rx.Impl.source(flatter, disp_me)

		# _disp_me = Observable.subscribe(rx, fn(_tag, _value) -> :ok end)
		# we return the new flattened sequence
		flatter
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

	* If the delay is set to too small value (e.g. `0`), then the first few
	  elements may be swalloed because no subscriber is available. This might
	  be changed in the future.
	"""
	@spec generate(Enumerable.t, non_neg_integer, non_neg_integer) :: Observable.t
	def generate(collection, delay \\ @rx_delay, timeout \\ @rx_timeout)
	def generate(collection, delay, timeout) do
		delayed_start(Generator.from(collection, delay), "generator.from", timeout)
	end

	@doc """
	The `map` functions takes an observable `rx` and applies function `fun` to
	each of its values.

	In ELM, this function is called `lift`, since it lifts a pure function into
	a signal, i.e. into an observable.

	In Reactive Extensions, this function is called `Select`.

	## Examples

	    iex> alias Reaxive.Rx
	    iex> Rx.naturals |> Rx.take(5) |> Rx.map(&(2+&1)) |> Rx.stream |> Enum.to_list
	    [2, 3, 4, 5, 6]

	"""
	@spec map(Observable.t, (... ->any) ) :: Observable.t
	def map(rx, fun) do
		rx |> Reaxive.Rx.Impl.compose(Sync.map(fun))
	end

	@tag timeout: 2_000
	@doc """
	Merges two or more event sequences in a non-deterministic order.

	The result sequences finishes after all sequences have finished without errors
	or immediately after the first error.

	## Examples

		iex> alias Reaxive.Rx
		iex> tens=Rx.naturals |> Rx.take(10)
		iex> fives=Rx.naturals |> Rx.take(5)
		iex> [tens, fives] |> Rx.merge() |> Rx.to_list |> Enum.sort
		[0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9]
	"""
	@spec merge(Observable.t, Observable.t) :: Observable.t
	def merge(rx1, rx2), do: merge([rx1, rx2])
	@spec merge([Observable.t]) :: Observable.t
	def merge(rxs) when is_list(rxs) do
		# Logger.info "Merging of #{inspect rxs}"
		{:ok, rx} = Reaxive.Rx.Impl.start("merge", @rx_defaults)
		rx |> Reaxive.Rx.Impl.compose(Sync.merge(length(rxs)))
		# subscribe to all originating sequences ...
		disposes = rxs |> Enum.map &Observable.subscribe(&1, rx)
		# and set the new disposables as sources.
		:ok = Reaxive.Rx.Impl.source(rx, disposes)
		rx
	end

	@doc """
	Generates all naturals numbers starting with `0`.

	## Examples

	    iex> alias Reaxive.Rx
	    iex> Rx.naturals |> Rx.take(5) |> Rx.stream |> Enum.to_list
	    [0, 1, 2, 3, 4]
	"""
	@spec naturals(non_neg_integer, non_neg_integer) :: t
	def naturals(delay \\ @rx_delay, timeout \\ @rx_timeout) do
		delayed_start(Generator.naturals(delay), "naturals", timeout)
	end

	@doc """
	The `never` function creates a sequence of events that never pushes anything.
	"""
	@spec never() :: Observable.t
	def never() do
		{:ok, new_rx} = Reaxive.Rx.Impl.start("never", @rx_defaults)
		silence = fn(event, acc) -> {:ignore, event, acc} end
		:ok = Reaxive.Rx.Impl.fun(new_rx, silence)
		new_rx
	end

	@doc """
	Multiplies all events of the sequence and returns the product as number

	## Examples

	    iex> alias Reaxive.Rx
	    iex> Rx.naturals |> Rx.take(5) |> Rx.map(&(&1 +1)) |> Rx.product
	    120

	    iex> alias Reaxive.Rx
	    iex> 1..5 |> Rx.generate(1) |> Rx.product
	    120       
	"""
	@spec product(Observable.t) :: number
	def product(rx) do
		rx |>	Reaxive.Rx.Impl.compose(Sync.product()) |> first
	end

	@doc """
	This function considers the past events to produce new events.
	Therefore this function is called in ELM `foldp`, folding over the past.

	In Elixir, it is the convention to call the fold function `reduce`, therefore
	we stick to this convention.

	The result of reduce is an event sequence with exactly one element. To get
	the scalar value, apply function `first` to it.

	The `reduce_fun` function is simple, applying the current event together with
	the accumulator producing a new accumulator. Finally, the accumulator is
	returned, when the source event stream is finished. The sum reducer could be
	implemented as

		def sum(rx) do
		  rx |> Rx.reduce(0, fn(x, acc) -> x + acc end)
		end

	For more complex reducing	functionalities, see the `Reaxive.Sync` module.
	"""
	@spec reduce(Observable.t, any, (any, any -> any)) :: Observable.t
	def reduce(rx, acc, reduce_fun) do
		Reaxive.Rx.Impl.compose(rx,
			Reaxive.Sync.simple_reduce(acc, reduce_fun))
	end

	@doc """
	The `return` function takes a `value` and creates an event sequence
	with exactly this `value` and terminates afterwards.

	It is essentially the same as

			generate([value])

	## Examples:

	    iex> alias Reaxive.Rx
	    iex> Rx.return(3) |> Rx.stream |> Enum.to_list
	    [3]

	    iex> alias Reaxive.Rx
	    iex>  Rx.return(5) |> Rx.stream |> Enum.to_list
	    [5]
	"""
	@spec return(any) :: Observable.t
	def return(value) do
		delayed_start(fn(rx) ->
				Observer.on_next(rx, value)
				:timer.sleep(@rx_delay)
				Observer.on_completed(rx, self)
			end, "return")
	end

	@doc """
	The function `start_with` takes a stream of events `prev_rx` and a collection.
	The resulting stream of events has all elements of `colletion`,
	followed by the events of `prev_rx`.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.generate([5]) |> Rx.start_with([0, 1, 2]) |> Rx.to_list
		[0, 1, 2, 5]
	"""
	@spec start_with(Observable.t, Enumerable.t) :: Observable.t
	def start_with(prev_rx, collection) do
		delayed_start(fn(rx) ->
			for e <- collection, do: Observer.on_next(rx, e)
			source = Observable.subscribe(prev_rx, rx)
			:ok = Reaxive.Rx.Impl.source(rx, source)
			Runnable.run(prev_rx)
		end, "start_with")
	end


	@doc """
	Converts a sequence of events into a (infinite) stream of events.

	This operator is not lazy, but eager, as it forces the subscribe and
	therefore the evaluation of the subscription.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.generate(1..5) |> Rx.stream |> Enum.to_list
		[1, 2, 3, 4, 5]
	"""
	@spec stream(Observable.t) :: Enumerable.t
	def stream(rx) do
		# queue all events in an process and collect them.
		# the accumulator is the disposable, which does not change.
		o = stream_observer()
		Stream.resource(
			# initialize the stream: Connect with rx and run it
			fn() -> 
				Observable.subscribe(rx, o) |> Runnable.run()
			end,
			# next element is taken from the message queue
			fn(acc) ->
				receive do
					{:on_next, value} -> {[value], acc}
					{:on_completed, _any} -> {:halt, acc}
					{:on_error, e} -> {:halt, {acc, e}} # should throw exception e!
				end
			end,
			# resource deallocation
			fn({{_id, rx2}, e}) -> Subscription.unsubscribe(rx2)
				 			e
			  ({_id, rx2}) -> Subscription.unsubscribe(rx2)
			  (sub) -> Subscription.unsubscribe(sub)
			end)
	end

	@doc "A simple observer function, sending tag and value as composed message to the process."
	@spec stream_observer(pid) :: Observer.t # ((any, any) -> {any, any}
	def stream_observer(pid \\ self) do
		fn(tag, value) -> send(pid, {tag, value}) end
	end

	@doc """
	Sums up all events of the sequence and returns the sum as number.

	## Examples

	   iex> alias Reaxive.Rx
	   iex> 1..5 |> Rx.generate(1) |> Rx.sum
	   15

	   iex> alias Reaxive.Rx
	   iex> Rx.naturals |> Rx.map(&(&1 +1)) |> Rx.take(5) |> Rx.sum
	   15
	"""
	@spec sum(Observable.t) :: number
	def sum(rx) do
		rx |> Reaxive.Rx.Impl.compose(Sync.sum()) |> first
	end

	@doc """
	This function produces only the first `n` elements of the event sequence.
	`n` must be positive.

	A negative `n` would take elements from the back (the last `n` elements.)
	This can be achieved by converting the sequence into a stream and back again:

		rx |> Rx.stream |> Stream.take(-n) |> Rx.generate

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take(10) |> Rx.to_list
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	"""
	@spec take(Observable.t, non_neg_integer) :: Observable.t
	def take(rx, n) when n >= 0 do
		rx |> Reaxive.Rx.Impl.compose(Sync.take(n))
	end

	@doc """
	Takes the first elements of the sequence while the
	predicate is true.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take_while(&(&1 < 5)) |> Rx.to_list
		[0, 1, 2, 3, 4]
	"""
	@spec take_while(Observable.t, (any -> boolean)) :: Observable.t
	def take_while(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.take_while(pred))
	end

	@doc """
	Takes the first elements of the sequence until the
	predicate is true.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take_until(&(&1 > 5)) |> Rx.to_list
		[0, 1, 2, 3, 4, 5]
	"""
	@spec take_until(Observable.t, (any -> boolean)) :: Observable.t
	def take_until(rx, pred) do
		rx |> Reaxive.Rx.Impl.compose(Sync.take_while(&(not pred.(&1))))
	end

	@doc """
	Produces a infinite sequence of `:tick`s, with a delay of `millis` milliseconds
	between each tick. 

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.ticks |> Rx.take(5) |> Rx.to_list
		[:tick, :tick, :tick, :tick, :tick] 
	"""
	@spec ticks(non_neg_integer) :: Observable.t
	def ticks(millis \\ 50) do
		delayed_start(Generator.ticks(millis))
	end
	

	@doc """
	Converts the event sequence into a regular list. Requires that the sequence
	is finite, otherwise this call does not finish.

	## Examples

		iex> alias Reaxive.Rx
		iex> Rx.naturals |> Rx.take(5) |> Rx.to_list
		[0, 1, 2, 3, 4]
	"""
	@spec to_list(Observable.t) :: [any]
	def to_list(rx) do
		rx |> stream |> Enum.to_list
	end
	

	@doc """
	Transform adds a composable transformation to an event sequence.
	If `obs` is a `Rx_Impl`, the transformation is added as composition,
	otherwise a new `Rx_Impl` is created to decouple `obs` and the transformation.
	"""
	@doc false
	# This functions does not work yet
	@spec transform(Observable.t, Sync.transform_t) :: Observable.t
	def transform(obs, transform) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start("transform", @rx_defaults)
		source = Observable.subscribe(obs, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, source)
		new_rx |> Reaxive.Rx.Impl.compose(transform)
	end

end


defimpl Runnable, for: PID do
	@doc """
	Running a PID means to send it the message `:run`. Only used for 
	explicitely spawned and custom implemented processes (.e.g for generator 
	functions).
	"""
  	def run(pid) do 
  		send(pid, :run)
  		:ok
  	end
end

defimpl Runnable, for: Tuple do
	@doc """
	Running a tuple assumes it represents the result of a subscription, 
	i.e. a tuple out of a `%Reaxive.Rx.Impl.Rx_t{}` and a 
	`%Reaxive.Subscription{}`.
	"""
	def run(p = { rx = %Reaxive.Rx.Impl.Rx_t{}, %Reaxive.Subscription{}}) do
		Reaxive.Rx.Impl.run(rx)
		p
	end
	
end