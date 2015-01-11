defmodule ReaxiveTest do
	use ExUnit.Case
	import ReaxiveTestTools

	test "subscribe and dispose" do
		{:ok, rx} = Reaxive.Rx.Impl.start("simple_subscriber", [auto_stop: false])
		{_, disp_me} = Reaxive.Rx.Impl.subscribe(rx, :me)
		{_, disp_you} = Reaxive.Rx.Impl.subscribe(rx, :you)

		assert Reaxive.Rx.Impl.subscribers(rx) == [:you, :me]

		Disposable.dispose(disp_me)
		assert Reaxive.Rx.Impl.subscribers(rx) == [:you]
		Disposable.dispose(disp_you)
		assert Reaxive.Rx.Impl.subscribers(rx) == []
	end

	test "send values to rx" do
		value = :x
		{:ok, rx} = Reaxive.Rx.Impl.start()
		{id, _disp_me} = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))
		Reaxive.Rx.Impl.on_next(rx, value)
		assert_receive {:on_next, ^value}
		Reaxive.Rx.Impl.on_completed(rx, self)
		assert_receive {:on_completed, ^id}
	end

	test "ensure monadic behavior in rx" do

		{:ok, rx} = Reaxive.Rx.Impl.start()
		# we need to link rx with the test process to receive the EXIT signal.
		Process.link(rx)
		Process.flag(:trap_exit, true)


		{id, disp_me} = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))
		Reaxive.Rx.Impl.on_completed(rx, self)
		assert_receive {:on_completed, ^id}

		Reaxive.Rx.Impl.on_next(rx, :x)
		disp_me.()
		# refute Process.alive? rx
		assert_receive {:EXIT, ^rx, _}
	end

	test "catch failing functions in rx" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(rx)
		Process.flag(:trap_exit, true)
		:ok = Reaxive.Rx.Impl.fun(rx, fn(_,_) -> 1/0 end) # a failing fun
		_disp_me = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))

		Reaxive.Rx.Impl.on_next(rx, :x)
		assert_receive {:on_error, _msg}
	end

	test "protocol for PID works" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(rx)
		Process.flag(:trap_exit, true)

		{id, _disp_me} = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))

		# now use the protocol functions on rx
		Observer.on_next(rx, :x)
		assert_receive {:on_next, :x}

		Observer.on_completed(rx, self)
		assert_receive {:on_completed, ^id}

		Observer.on_next(rx, :oh_no_this_cannot_delivered!)
		assert_receive {:EXIT, ^rx, _}
	end

	test "chaining two Rx streams" do
		{:ok, rx1} = Reaxive.Rx.Impl.start("rx1", [auto_stop: false])
		Process.link(rx1) #  just to ensure that failures appear also here!

		{:ok, rx2} = Reaxive.Rx.Impl.start("rx2", [auto_stop: false])
		Process.link(rx2) #  just to ensure that failures appear also here!
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		{id, _disp_me} = Reaxive.Rx.Impl.subscribe(rx2, call_me)

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_next, :x}

		Reaxive.Rx.Impl.on_completed(rx1, self)
		assert_receive {:on_completed, ^id}

		assert Reaxive.Rx.Impl.subscribers(rx1) == []
		assert Reaxive.Rx.Impl.subscribers(rx2) == []
	end

	test "chaining two Rx streams with failures" do
		Process.flag(:trap_exit, true)
		{:ok, rx1} = Reaxive.Rx.Impl.start("chain 1", [auto_stop: false])
		Process.link(rx1) #  just to ensure that failures appear also here!

		{:ok, rx2} = Reaxive.Rx.Impl.start("chain 2", [auto_stop: false])
		Process.link(rx2) #  just to ensure that failures appear also here!
		:ok = Reaxive.Rx.Impl.fun(rx2, fn(_) -> 1/0 end) # will always fail
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		{id, _disp_me} = Reaxive.Rx.Impl.subscribe(rx2, call_me)

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_error, _}

		# if Process.alive?(rx2), then:
		assert Reaxive.Rx.Impl.subscribers(rx2) == []
		assert Reaxive.Rx.Impl.subscribers(rx1) == []

		Reaxive.Rx.Impl.on_completed(rx1, self)
		refute_receive {:on_completed, ^id}
	end

	test "Stopping processes after unsubscribe" do
		# {:ok, rx} = Reaxive.Rx.Impl.start("rx", [auto_stop: true])
		{:ok, rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.source(rx, {self, fn()-> :ok end})
		{_, disp_me} = Reaxive.Rx.Impl.subscribe(rx, :me)
		{_, disp_you} = Reaxive.Rx.Impl.subscribe(rx, :you)

		assert Reaxive.Rx.Impl.subscribers(rx) == [:you, :me]

		Disposable.dispose(disp_me)
		assert Reaxive.Rx.Impl.subscribers(rx) == [:you]
		Disposable.dispose(disp_you)
		refute Process.alive?(rx)
	end

	test "Stopping processes after completion" do
		{:ok, rx1} = Reaxive.Rx.Impl.start("rx1", [auto_stop: true])
		Process.link(rx1) #  just to ensure that failures appear also here!

		{:ok, rx2} = Reaxive.Rx.Impl.start("rx2", [auto_stop: true])
		Process.link(rx2) #  just to ensure that failures appear also here!
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		{id, disp_me} = Reaxive.Rx.Impl.subscribe(rx2, call_me)

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_next, :x}

		Reaxive.Rx.Impl.on_completed(rx1, self)
		assert_receive {:on_completed, ^id}
		disp_me.() # we call this, because our functional observer is too stupid to do it by itself

		refute Process.alive?(rx1)
		refute Process.alive?(rx2)
	end

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

end
