defmodule Reaxive.Transducer do
	require Logger

	@moduledoc """
	A transducer library inspired by [Clojure](http://clojure.org/transducers).
	
	We follow at first the path of Ritch Hickey's Strange Loop 2014 Talk 
	(https://www.youtube.com/watch?v=6mTbuzafcII)
	"""
	@doc "Transducer map"
	def mapping(fun) do
		fn(step) -> 
			fn(elem, rest) -> 
				# Logger.debug("mapping: rest = #{inspect rest}, elem = #{inspect elem}")
				step . (rest, fun.(elem))  end
		end	
	end

	@doc "Transducer filter"
	def filtering(pred) do
		fn(step) ->
			fn(elem, rest) -> case (pred.(elem)) do
				true  -> step . (rest, elem)
				false -> rest
				end
			end
		end
	end

	@doc "Transducer cat"
	def cat() do
		fn(step) -> 
			fn(elem, rest) -> Enum.reduce(rest, elem, step) end
		end
	end

	@doc "Transducer mapcat"
	def mapcatting(fun) do
		compose(mapping(fun), cat)
	end

	@doc "Compose two functions"
	def compose(f1, f2) do
		fn(arg) -> f2.(f1.(arg)) end
	end
	
	@doc "joins a list and element, the element is the new head"
	def join(list, elem), do: [elem | list]

	@doc "Map on lists"
	def map(list, f) do
		list |> Enum.reduce([], mapping(f).(&join/2)) |> Enum.reverse
	end
	



end