defmodule ReaxiveTest do
	use ExUnit.Case

	test "subscribe and dispose" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		disp_me = Reaxive.Rx.Impl.subscribe(rx, :me)
		disp_you = Reaxive.Rx.Impl.subscribe(rx, :you)

		assert Reaxive.Rx.Impl.subscribers(rx) == [:you, :me]

		Disposable.dispose(disp_me)
		assert Reaxive.Rx.Impl.subscribers(rx) == [:you]
		Disposable.dispose(disp_you)
		assert Reaxive.Rx.Impl.subscribers(rx) == []
	end

	test "send values to rx" do
		value = :x
		{:ok, rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(rx, &identity/1) 
		disp_me = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))
		Reaxive.Rx.Impl.on_next(rx, value)
		assert_receive {:on_next, value}
		Reaxive.Rx.Impl.on_completed(rx)
		assert_receive {:on_completed, nil}		
	end

	test "ensure monadic behavior in rx" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(rx)
		Process.flag(:trap_exit, true)

		:ok = Reaxive.Rx.Impl.fun(rx, &identity/1) 
		disp_me = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))
		Reaxive.Rx.Impl.on_completed(rx)
		assert_receive {:on_completed, nil}

		# we need to link rx with the test process to receive the EXIT signal.
		# catch_exit(Reaxive.Rx.Impl.on_next(rx, :x))
		Reaxive.Rx.Impl.on_next(rx, :x)
		assert_receive {:EXIT, ^rx, _}
	end

	test "catch failing functions in rx" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(rx)
		Process.flag(:trap_exit, true)
		:ok = Reaxive.Rx.Impl.fun(rx, fn(_) -> 1/0 end) # a failing fun
		disp_me = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))

		Reaxive.Rx.Impl.on_next(rx, :x)
		assert_receive {:on_error, msg}
	end

	test "protocol for PID works" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(rx)
		Process.flag(:trap_exit, true)

		:ok = Reaxive.Rx.Impl.fun(rx, &identity/1) 
		disp_me = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))

		# now use the protocol functions on rx
		Observer.on_next(rx, :x)
		assert_receive {:on_next, :x}

		Observer.on_completed(rx)
		assert_receive {:on_completed, nil}

		Observer.on_next(rx, :x)
		assert_receive {:EXIT, ^rx, _}
	end

	test "chaining two Rx streams" do
		{:ok, rx1} = Reaxive.Rx.Impl.start()
		Process.link(rx1) #  just to ensure that failures appear also here!
		:ok = Reaxive.Rx.Impl.fun(rx1, &identity/1) 

		{:ok, rx2} = Reaxive.Rx.Impl.start()
		Process.link(rx2) #  just to ensure that failures appear also here!
		:ok = Reaxive.Rx.Impl.fun(rx2, &identity/1) 
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		disp_me = Reaxive.Rx.Impl.subscribe(rx2, call_me)

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_next, :x}

		Reaxive.Rx.Impl.on_completed(rx1)
		assert_receive {:on_completed, nil}

		assert Reaxive.Rx.Impl.subscribers(rx1) == []
		assert Reaxive.Rx.Impl.subscribers(rx2) == []	
	end

	test "chaining two Rx streams with failures" do
		Process.flag(:trap_exit, true)
		{:ok, rx1} = Reaxive.Rx.Impl.start()
		Process.link(rx1) #  just to ensure that failures appear also here!
		:ok = Reaxive.Rx.Impl.fun(rx1, &identity/1) 

		{:ok, rx2} = Reaxive.Rx.Impl.start()
		Process.link(rx2) #  just to ensure that failures appear also here!
		:ok = Reaxive.Rx.Impl.fun(rx2, fn(x) -> 
			IO.puts "Yeah #{inspect x}"
			1/0 end) # will always fail 
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		disp_me = Reaxive.Rx.Impl.subscribe(rx2, call_me)

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_error, _}

		Reaxive.Rx.Impl.on_completed(rx1)
		assert_receive {:on_completed, nil}

		assert Reaxive.Rx.Impl.subscribers(rx1) == []
		assert Reaxive.Rx.Impl.subscribers(rx2) == []	
	end

	def simple_observer_fun(pid) do
		fn(tag, value ) -> send(pid, {tag, value}) end
	end

	def identity(x), do: x

	def drain_messages(wait_millis \\ 50)
	def drain_messages(wait_millis) when is_integer(wait_millis) do
		receive do
		after wait_millis -> :ok
		end
		drain_messages([])
	end
	def drain_messages(accu) when is_list(accu) do
		receive do
			msg     -> drain_messages([msg | accu])
			after 0 -> Enum.reverse(accu)
		end
	end

	defimpl Observer, for: Function do
		def on_next(observer, value), do: observer.(:on_next, value)
		def on_error(observer, exception), do: observer.(:on_error, exception)
		def on_completed(observer), do: observer.(:on_completed, nil)
	end
end
