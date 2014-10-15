defmodule Reaxive.Transducer do
	require Logger

	@moduledoc """
	A transducer library inspired by [Clojure](http://clojure.org/transducers).
	
	We follow at first the path of Ritch Hickey's Strange Loop 2014 Talk 
	(https://www.youtube.com/watch?v=6mTbuzafcII)

	A transducers is a function, that expects a `step` function. The `step`
	function  decouples how the transducers work is conjoined, e.g. into an
	list, a stream or  an observable. The `step` function may be called 0, 1,
	or even more times. The  transducer must call `step` with the previous
	`result` as next result as first argument.

	######################################################
	## New theory about transducers

	A transducer takes an element and a current reduced value. It calculates
	a (new, unchanged or modified) element and a (new, unchanged or modified)
	reduced value. With this, it calls the next transducer (which is given as 
	a parameter within the closure defining the transducer), if further processing 
	of the element is required. 

	### Consequences

	* Creating the final reduced valued, i.e. conjoining a list or sending a value
	  to a an observer, is also a transducer. 
	* The return value of a transducer is a tuple similar to `Enumerable.acc` which
	  controls the reducing process, but with three elements, since the element and
	  the reduced value are moved towards the next  nested call. 
	* A filter transducer simply does call the next transducer, if the element is 
	  to be filtered. 
	* A take transducer returns `{:halt, value}` to stop the reducing process, if 
	  the take condition is true. 

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

	@doc "apply first t1, then t2"
	def make_transducer(t1, t2) do # t1, t2 :: (make_acc) -> ((a, b) -> {:cont, x, y})
		fn(make_acc) -> 
			trans2 = t2 . (make_acc)
			trans1 = t1 . (trans2)
			trans1
		end
	end

	@doc "A manually combined transducer, that first mapps the element and then filters it."
	def mapped_filtering(mf, p) do
		fn(make_acc) -> 
			f = filtering(p) # :: (a, b) -> {acc_to_do, a, b})
			m = mapping(mf) #  :: (a, b) -> {acc_to_do, c, b}
			t = make_transducer(m, f)
			t.(make_acc)
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
		mapper = mapping(f) . (&prepend/2)
		list |> Enum.reduce([], mapper)  |> Enum.reverse
	end
	
	@doc "Filter on lists"
	def filter(list, pred) do
		f = filtering(pred) . (&prepend/2)
		list |> Enum.reduce([], f) |> Enum.reverse
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

end