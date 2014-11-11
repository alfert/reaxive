defmodule ReaxiveTestTools do
		
	require Logger

	def simple_observer_fun(pid) do
		fn(tag, value ) -> 
			# Logger.debug "simple_observer: #{inspect {tag, value}}"
			send(pid, {tag, value}) 
		end
	end

	def identity(x), do: x

	def inc(x), do: x+1
	def double(x), do: x+x
	def p(x), do: IO.inspect x

end	