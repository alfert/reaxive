defmodule ReaxiveTestTools do
		
	def simple_observer_fun(pid) do
		fn(tag, value ) -> send(pid, {tag, value}) end
	end

	def identity(x), do: x


end	