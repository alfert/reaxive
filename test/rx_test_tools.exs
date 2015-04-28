defmodule ReaxiveTestTools do
		
	require Logger

	def simple_observer_fun(%Reaxive.Rx.Impl.Rx_t{pid: pid = rx}) do
		Runnable.run(rx)
		simple_observer_fun(pid)
	end
	def simple_observer_fun(pid) when is_pid(pid) do
		fn(tag, value ) -> 
			# Logger.debug "simple_observer: #{inspect {tag, value}} "<> 
			# 	"send to #{inspect pid} from #{inspect self}"
			send(pid, {tag, value}) 
		end
	end

	def identity(x), do: x

	def inc(x), do: x+1
	def double(x), do: x+x
	def p(x), do: IO.inspect x


	def run_subscription({ rx = %Reaxive.Rx.Impl.Rx_t{}, %Reaxive.Subscription{}}) do
		Runnable.run(rx)
	end


	defmodule EmptySubscription do
		@moduledoc """
		This subscription does nothing. It is always unsubscribed 
		and requires no running process. 
		"""
		defstruct pid: self()

		def new, do: %__MODULE__{}

		defimpl Subscription do
			def unsubscribe(sub), do: :ok
			def is_unsubscribed?(sub), do: true
		end

		defimpl Runnable do
		  def run(_), do: :ok
		end
	end

end	