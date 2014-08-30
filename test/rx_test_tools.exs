defmodule ReaxiveTestTools do
		
	require Logger

	def simple_observer_fun(pid) do
		fn(tag, value ) -> 
			Logger.debug "simple_observer: #{inspect {tag, value}}"
			send(pid, {tag, value}) 
		end
	end

	def identity(x), do: x


end	