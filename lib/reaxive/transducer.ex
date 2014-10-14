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

	
	"""
	
	@type step_fun(a, b, c, d) ::  ((a, b) -> {c, d})

	@doc "Transducer map"
	@spec mapping((a -> c)) :: step_fun(a, b, c, d) when a: any, b: any, c: any, d: any
	def mapping(fun) do
		fn(step) -> 
			fn(elem, result) -> 
				Logger.debug("mapping: result = #{inspect result}, elem = #{inspect elem}")
				step . (fun.(elem), result)  end
		end	
	end

	@doc "Transducer filter"
	@spec filtering((a -> c)) :: step_fun(a, b, c, d) when a: any, b: any, c: boolean, d: any
	def filtering(pred) do
		fn(step) ->
			fn(elem, result) -> 
				Logger.debug("filtering: result = #{inspect result}, elem = #{inspect elem}")
				if (pred.(elem)), do: step . (elem, result), else: result
			end
		end
	end

	@doc "Transducer cat"
	def cat() do
		fn(step) -> 
			fn(elem, result) -> Enum.reduce(result, elem, step) end
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
	
	@doc "Compose two functions"
	def compose(f1, f2) when is_function(f1, 1), do: fn(arg) -> f2.(f1.(arg)) end
	def compose(f1, f2) when is_function(f1, 2), do: fn(arg1, arg2) -> f2.(f1.(arg1, arg2)) end
	
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
		list |> Enum.reduce(steps . (&prepend/2))		
	end
			

end