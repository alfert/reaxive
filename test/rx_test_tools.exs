defmodule ReaxiveTestTools do
		
	def simple_observer_fun(pid) do
		fn(tag, value ) -> send(pid, {tag, value}) end
	end

	def identity(x), do: x

	defimpl Observer, for: Function do
		def on_next(observer, value), do: observer.(:on_next, value)
		def on_error(observer, exception), do: observer.(:on_error, exception)
		def on_completed(observer), do: observer.(:on_completed, nil)
	end

end	