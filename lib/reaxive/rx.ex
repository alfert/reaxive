defmodule Reaxive.Rx do
	
	@spec map(Observable.t, (... ->any) ) :: Observable.t
	def map(rx, fun) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		:ok = Reaxive.Rx.Impl.fun(new_rx, fun)
		new_rx
	end
	
	@spec generate(Enumerable.t, pos_integer) :: Observable.t
	def generate(collection, delay \\ 100) do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(rx, &(&1)) # identity fun
		send_values = fn() -> 
			receive do
				after delay -> :ok
			end
			collection |> Enum.each &Observer.on_next(rx, &1)
			Observer.on_completed(rx)
		end
		spawn(send_values)
		rx
	end
	
	# a simple sink
	@spec as_text(Observable.t) :: :none
	def as_text(rx) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		:ok = Reaxive.Rx.Impl.fun(new_rx, fn(v) -> IO.inspect v end)
		:none
	end
	
	def collect(rx) do
		{:ok, new_rx} = Reaxive.Rx.Impl.start()
		disp = Reaxive.Rx.Impl.subscribe(rx, new_rx)
		:ok = Reaxive.Rx.Impl.source(new_rx, disp)
		# TODO: Here we need the accumulator ....
		# :ok = Reaxive.Rx.Impl.fun(new_rx, fun)
		new_rx		
	end
	

end
