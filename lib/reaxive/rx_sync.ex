defmodule Reaxive.Sync do
	@moduledoc """
	Implements the Reaxive Extensions as synchronous function composition similar to
	Elixir's `Enum` and `Stream` libraries, but adheres to the `Observable` protocol.

	# Design Idea

	The operators are used in two phases. First, they are composed to a single function,
	which represents the sequence of the operators together with their initial accumulator
	list. The list might be empty, if no accumulator is used by the given operators (e.g.
	if using `map` and `filter` only).

	The second phase is the execution phase. Similar to transducers, the composed operators
	make no assumptions how the calculated values are used and how the accumulators are stored
	between two operator evaluations. This could be done as inside `Rx.Impl`, but other
	implementations are possible. The result, i.e. which send to the consumers, is always the head
	of the accumulator, unless the reason tag is `:ignore` or `:halt`.

	"""

	require Logger

	@compile(:inline)

	@type reason_t :: :cont | :ignore | :halt | :error

	@type acc_t :: list
	@type tagged_t :: {reason_t, any}
	@type reduce_t :: {tagged_t, acc_t, acc_t}
	@type reduce_fun_t :: ((tagged_t, acc_t, acc_t) -> reduce_t)
	@type step_fun_t :: ((any, acc_t, any, acc_t) -> reduce_t)
	@type transform_t :: {reduce_fun_t, any}


	@doc """
	This macro encodes the default behavior for reduction functions, which is capable of
	ignoring values, of continuing work with `:on_next`, and of piping values for `:on_completed`
	and `:on_error`.

	You must provide the implementation for the `:on_next` branch. Implicit parameters are the
	value `v` and the accumulator list `acc`, the current accumulator `a` and the new accumulator
	`new_acc`.

	"""
	defmacro default_behavior(accu \\ nil, do: clause) do
		quote do
			{
			fn
				({{:on_next, var!(v)}, [var!(a) | var!(acc)], var!(new_acc)}) -> unquote(clause)
				({{:on_completed, nil}, [a | acc], new_acc})     -> halt(acc, a, new_acc)
				({{:on_completed, v}, [a | acc], new_acc})     -> emit_and_halt(acc, a, new_acc)
				{:cont, {:on_completed, v}, [a |acc], new_acc} -> emit_and_halt(acc, a, new_acc)
				({:ignore, v, [a | acc], new_acc})          -> ignore(v, acc, a, new_acc)
				({{:on_error, v}, [a | acc], new_acc})      -> error(v, acc, a, new_acc)
			end,
			unquote(accu)
			}
		end
	end

	## These macros build up the return values of the reducers.
	defmacro halt(acc, new_a, new_acc), do:
		quote do: {{:on_completed, unquote(nil)}, unquote(acc), [unquote(new_a) | unquote(new_acc)]}
	defmacro emit_and_halt(acc, new_a, new_acc), do:
		quote do: {:cont, {:on_completed, unquote(new_a)}, unquote(acc), [unquote(new_a) | unquote(new_acc)]}
	defmacro error(error, acc, new_a, new_acc), do:
		quote do: {{:on_error, unquote(error)}, unquote(acc), [unquote(new_a) | unquote(new_acc)]}
	defmacro emit(v, acc, new_a, new_acc), do:
		quote do: {{:on_next, unquote(v)}, unquote(acc), [unquote(new_a) | unquote(new_acc)]}
	defmacro ignore(v, acc, new_a, new_acc), do:
		quote do: {:ignore, unquote(v), unquote(acc), [unquote(new_a) | unquote(new_acc)]}

	@doc "Reducer function for filter"
	@spec filter(((any) -> boolean)) :: {reduce_fun_t, any}
	def filter(pred) do
		default_behavior do
			case pred.(v) do
				true  -> emit(v, acc, a, new_acc)
				false -> ignore(v, acc, a, new_acc)
			end
		end
	end

	@doc "Reducer function for map."
	@spec map(((any) -> any)) :: {reduce_fun_t, any}
	def map(fun) do
		default_behavior do: emit(fun.(v), acc, a, new_acc)
	end

	@doc "Reducer function for `take`"
	def take(n) when n >= 0 do
		default_behavior(n) do
			if a == 0 do
				r = halt(acc, a, new_acc)
				# IO.puts "a == 0, r = #{inspect r}"
				r
			else
				emit(v, acc, a-1, new_acc)
			end
		end
	end

	@doc "Reducer for `take_while`"
	@spec take_while((any -> boolean)) :: {reduce_fun_t, any}
	def take_while(pred) do
		default_behavior do
			case pred.(v) do
				true  -> emit(v, acc, a, new_acc)
				false -> halt(acc, a, new_acc)
			end
		end
	end

	@doc "Reducer function for `drop`"
	def drop(n) when n >= 0 do
		default_behavior(n) do
			if a == 0 do
				r = emit(v, acc, a, new_acc)
				# IO.puts "a == 0, r = #{inspect r}"
				r
			else
				ignore(v, acc, a-1, new_acc)
			end
		end
	end

	@doc "Reducer for `drop_while`"
	@spec drop_while((any -> boolean)) :: {reduce_fun_t, any}
	def drop_while(pred) do
		default_behavior(:none) do
			case {a, pred.(v)} do
				{:none, true}  -> ignore(v, acc, a, new_acc)
				{:none, false}  -> emit(v, acc, :some, new_acc)
				{:some, _} -> emit(v, acc, a, new_acc)
			end
		end
	end

	@doc """
	This function takes an initial accumulator and three step functions. The step functions
	have as first parameter the current value, followed by the list of next accumulators, the current
	accumulator, and the list of future accumulators. The three functions handle the situation of
	the next value, of completion of the stream and of the error situation.

	Handling the `ignore` case is part of `full_behavior` and cannot be handled by the step functions.

	It is best to use the `halt`, `emit`, `ignore` and `error` macros to produce proper return
	values of the three step functions.
	"""
	@spec full_behavior(any, step_fun_t, step_fun_t, step_fun_t) :: {reduce_fun_t, any}
	def full_behavior(accu \\ nil, next_fun, comp_fun, error_fun) do
		{
			fn
				({{:on_next, v}, [a | acc], new_acc})      -> next_fun . (v, acc, a, new_acc)
				({{:on_completed, v}, [a | acc], new_acc}) -> comp_fun . (v, acc, a, new_acc)
				({{:on_error, v}, [a | acc], new_acc})     -> error_fun . (v, acc, a, new_acc)
				({:ignore, v, [a | acc], new_acc})         -> ignore(v, acc, a, new_acc)
			end,
			accu
		}
	end

	@doc """
	Takes a next function and an accu and applies it to each value. Emits only
	the accumulator after the source sequence is finished.
	"""
	@spec reduce(any, step_fun_t) :: transform_t
	def reduce(accu \\ nil, next_fun) do
		full_behavior(accu,
			next_fun,
			fn(_v, acc, a, new_acc) -> emit_and_halt(acc, a, new_acc) end,
			fn(v, acc, a, new_acc) -> error(v, acc, a, new_acc) end)
	end

	@doc "Returns the sum of input events as sequence with exactly one event."
	def sum() do
		simple_reduce(0, &Kernel.+/2)
	end

	@doc "Returns the product of input events as sequence with exactly one event."
	def product() do
		simple_reduce(1, &Kernel.*/2)
	end

	@doc "Reducer for a simple reducer"
	def simple_reduce(accu, red_fun) do
		reduce(accu,
			fn(v, acc, a, new_acc) -> ignore(v, acc, red_fun . (v, a), new_acc) end)
	end

	@doc "Reducer for merging `n` streams"
	def merge(n) when n > 0 do
		full_behavior(n,
			fn(v, acc, k, new_acc) -> emit(v, acc, k, new_acc) end,
			fn
				(_v, acc, 1, new_acc) -> halt(acc, 1, new_acc)  # last complete => complete merge
				(v, acc, k, new_acc) -> ignore(v, acc, k-1, new_acc) # ignore complete
			end,
			fn(v, acc, k, new_acc) -> error(v, acc, k, new_acc) end
		)
	end

	@doc "a filter passing through only distinct values"
	@spec distinct(Set.t) :: {reduce_fun_t, any}
	def distinct(empty_set) do
		default_behavior(empty_set) do
			case (Set.member?(a, v)) do
				true  -> ignore(v, acc, a, new_acc)
				false -> emit(v, acc, Set.put(a, v), new_acc)
			end
		end
	end

	@doc "a filter for repeating values, i.e. only changed values can pass"
	@spec distinct_until_changed() :: {reduce_fun_t, any}
	def distinct_until_changed() do
		# the accu is an option type with of some or none elements.
		# None elements means, that the accu is not used.
		default_behavior(:none) do
			case a do
				{:some, ^v}  -> ignore(v, acc, a, new_acc) # ignore repeating value
				{:some, _}  -> emit(v, acc, {:some, v}, new_acc) # accu and v are different
				:none       -> emit(v, acc, {:some, v}, new_acc) # emit very first value
			end
		end
	end

end
