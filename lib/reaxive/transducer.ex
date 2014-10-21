defmodule Reaxive.Transducer do
	require Logger

	@moduledoc """
	A transducer library inspired by [Clojure](http://clojure.org/transducers).
	We follow the path of Ritch Hickey's Strange Loop 2014 Talk 
	(https://www.youtube.com/watch?v=6mTbuzafcII)

	### What is a transducer?

	A transducers is a reducer-like function, that decouples how the
	the current value is taken from the source and how the new accumulator 
	is build up. The decoupling is realized with an additional function
	parameter, which is essentially the next transducer to call or a functional 
	to determine the accumulator.

	A transducer function takes an element and a current reduced value. It
	calculates a (new, unchanged or modified) element and a (new, unchanged or
	modified) reduced value. With this, it calls the next transducer (which is
	given as a parameter within the closure defining the transducer), if
	further processing  of the element is required.

	### Consequences

	* Creating the final reduced valued, i.e. conjoining a list or sending a value
	  to a an observer, is also a transducer. 
	* The return value of a transducer is a tuple similar to `Enumerable.acc` which
	  controls the reducing process, but with three elements, since the element and
	  the reduced value are moved towards the next nested call. 
	* A filter transducer simply does call the next transducer, if the element is 
	  to be filtered. 
	* A take transducer returns `{:halt, value}` to stop the reducing process, if 
	  the take condition is true. 
	* A transducer build up from many steps does not require to build up any interim 
	  temporal data structures. This is different from the `Enum` functions in Elixir - 
	  however those are very fast by using Erlang's built-in functions. On the other 
	  side, this feature makes transducer a perfect vehicle to construct sequential 
	  Reactive Extension operators. 

	### How to use transducers with Observables?

	* The final transducer does not build up a data structure but sends the reduced
	  value to all observers. 
	* Events coming from an observable are fed into the transducer chain to calculate
	  the next values.
	* Building Reactive Extension operator with transducers requires a generic constructor
	  which handles all the subscription stuff as well as handling the return values
	  of the transducer chain properly. 

	### Open Issues

	* How to deal with state, e.g. for partitioning?
	* Are list operations automatically reversed? This could be a default parameter
	  of the reducing process, which is only considered for list creations. 
	* How to deal with exceptions? If we want to support observables, we must catch 
	  them and convert them into an {:error, elem} value. Perhaps this makes the 
	  transducers to a monad and is also a way to handle state properly. Rough idea: 
	  Elements are passed as {:cont, elem} is everything is ok, errors as {:error, elem}. 
	  In the latter case, no operations are usually allowed but the value is propagated to 
	  the final transducer (exception: `OnException` transducer as in RX.)
	
	"""
	
	#@compile :inline_list_funcs
	#@compile :inline

	@typedoc "Similar to Enumerable.acc"
	@type acc_to_do :: :cont | :halt 

	@doc "Transducer map"
	def mapping(fun) do
		fn(make_acc) -> 
			fn({:cont, elem}, result) -> 
				# Logger.debug("mapping: result = #{inspect result}, elem = #{inspect elem}")
				make_acc . ({:cont, fun.(elem)}, result)  
			   ({:halt, elem}, result) -> make_acc . ({:halt, elem}, result)
			end
		end	
	end

	@doc "Transducer filter"
	def filtering(pred) do
		fn(make_acc) ->
			fn({:cont, elem}, result) -> 
				# Logger.debug("filtering: result = #{inspect result}, elem = #{inspect elem}")
				if (pred.(elem)), do: make_acc . ({:cont, elem}, result), else: {:cont, result}
				({:halt, elem}, result) -> make_acc . ({:halt, elem}, result)
			end
		end
	end

	@doc "A list prepending transducer, the last step inside a transducer stack"
	def prepending() do 
		fn({:cont, elem}, result) -> {:cont, [elem | result]}
		  ({:halt, elem}, result) -> {:halt, result}
		end
	end

	@doc """
	Composes two or more functions (with one argument) and returns the 
	composition as a single function with one argument.
	"""
	def comp(ts) when is_list(ts), do: 
		ts |> Enum.reduce(fn(x) -> (x) end, &comp/2)
	def comp(f, g), do: fn(x) -> f . (g . (x)) end
	def comp(f1, f2, f3), do: comp([f1, f2, f3])
	def comp(f1, f2, f3, f4), do: comp([f1, f2, f3, f4])
	def comp(f1, f2, f3, f4, f5), do: comp([f1, f2, f3, f4, f5])
	def comp(f1, f2, f3, f4, f5, f6), do: comp([f1, f2, f3, f4, f5, f6])

	@doc "A manually combined transducer, that first mapps the element and then filters it."
	def mapped_filtering(mf, p) do
		fn(make_acc) -> 
			f = filtering(p) # :: (a, b) -> {acc_to_do, a, b})
			m = mapping(mf) #  :: (a, b) -> {acc_to_do, c, b}
			comp(m, f).(make_acc)
		end
	end

	@doc "Transducer cat"
	def cat() do
		fn(step) -> 
			fn(elem, result) -> {:cont, Enum.reduce(result, elem, step)} end
		end
	end

	@doc "Transducer mapcat"
	def mapcatting(fun) do
		compose(mapping(fun), cat)
	end

	@doc "Transducer take-while"
	def taking_while(pred) do
		fn(step) ->
			fn(elem, result) -> 
				if (pred.(elem)), 
					do: {:cont, step.(elem, result)}, 
					else: {:halt, result}
			end
		end
	end
	
	@doc "Compose two transducer functions"
	# def compose(f1, f2) when is_function(f1, 1), do: fn(arg) -> f2.(f1.(arg)) end
	def compose(f1, f2) when is_function(f1, 2), do: 
		fn(elem1, acc1) -> 
			case f1.(elem1, acc1) do
				{:cont, acc2} -> f2.(elem1, acc2)
				{:halt, acc2} -> acc2 # stop processing
			end
		end
	
	@doc "joins a list and element, the element is the new head"
	def prepend(elem, list) when is_list(list), do: [elem | list]
	def prepend(elem, list) do
		Logger.error ("wrong types! elem is #{inspect elem}, list is #{inspect list}")
		raise "Wrong Types!"
	end

	@doc "Map on lists"
	def map(list, f) do
		list |> transduce(mapping(f)) |> Enum.reverse
	end
	
	@doc "Filter on lists"
	def filter(list, pred) do
		list |> transduce(filtering(pred)) |> Enum.reverse
	end
	
	@doc "Take while on lists"
	def take_while(list, pred) do
		f = taking_while(pred) . (&prepend/2)
		list |> Enumerable.reduce({:cont, []}, f) |> elem(1)|> Enum.reverse
	end

	def transduce(list, steps) when is_function(steps) do
		list |> do_trans({:cont, []}, steps . (prepending()))
	end
	
	@doc """
	Recursive transducing on lists as a reducing function controlled by `acc_to_do`
	"""
	def do_trans([], {_, acc}, _f), do: acc
	def do_trans(_, {:halt, acc}, _f), do: acc
	def do_trans([head | tail], {:cont, acc}, f) do
		do_trans(tail, f.({:cont, head}, acc), f)
	end		
	def do_trans(coll, a = {:cont, acc}, f) do
		{:done, v} = Enumerable.reduce(coll, a, fn(x, ac) -> f.({:cont, x}, ac) end)
		v
	end
end