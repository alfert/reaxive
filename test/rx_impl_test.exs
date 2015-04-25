defmodule ReaxiveTest do
	use ExUnit.Case
	import ReaxiveTestTools
	alias Reaxive.Rx.Impl.Rx_t

	test "subscribe and dispose" do
		{:ok, rx} = Reaxive.Rx.Impl.start("simple_subscriber", [auto_stop: false])
		{_, disp_me} = Reaxive.Rx.Impl.subscribe(rx, :me)
		{_, disp_you} = Reaxive.Rx.Impl.subscribe(rx, :you)

		assert Reaxive.Rx.Impl.subscribers(rx) == [:you, :me]

		Subscription.unsubscribe(disp_me)
		assert Reaxive.Rx.Impl.subscribers(rx) == [:you]
		Subscription.unsubscribe(disp_you)
		assert Reaxive.Rx.Impl.subscribers(rx) == []
	end

	test "send values to rx" do
		value = :x
		{:ok, rx} = Reaxive.Rx.Impl.start()
		{rx2, _disp_me} = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))
		Reaxive.Rx.Impl.on_next(rx, value)
		assert_receive {:on_next, ^value}
		Reaxive.Rx.Impl.on_completed(rx, self)
		id = process rx2
		assert_receive {:on_completed, ^id}
	end

	test "ensure monadic behavior in rx" do

		{:ok, rx} = Reaxive.Rx.Impl.start()
		# we need to link rx with the test process to receive the EXIT signal.
		Process.link(process rx)
		Process.flag(:trap_exit, true)

		{rx2, disp_me} = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))
		Reaxive.Rx.Impl.on_completed(rx, self)
		id2 = process rx2
		assert_receive {:on_completed, ^id2}

		Reaxive.Rx.Impl.on_next(rx, :x)
		# disp_me.()
		Subscription.unsubscribe(disp_me)
		# refute Process.alive? rx
		id = process rx
		assert_receive {:EXIT, ^id, _}
	end

	test "catch failing functions in rx" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(process rx)
		Process.flag(:trap_exit, true)
		:ok = Reaxive.Rx.Impl.fun(rx, fn(_,_) -> 1/0 end) # a failing fun
		_disp_me = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))

		Reaxive.Rx.Impl.on_next(rx, :x)
		assert_receive {:on_error, _msg}
	end

	test "protocol for PID works" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		Process.link(process rx)
		Process.flag(:trap_exit, true)

		{rx2, _disp_me} = Reaxive.Rx.Impl.subscribe(rx, simple_observer_fun(self))

		# now use the protocol functions on rx
		Observer.on_next(rx, :x)
		assert_receive {:on_next, :x}

		Observer.on_completed(rx, self)
		id2 = process rx2
		assert_receive {:on_completed, ^id2}

		Observer.on_next(rx, :oh_no_this_cannot_delivered!)
		id1 = process rx
		assert_receive {:EXIT, ^id1, _}
	end

	test "chaining two Rx streams" do
		{:ok, rx1} = Reaxive.Rx.Impl.start("rx1", [auto_stop: false])
		Process.link(process rx1) #  just to ensure that failures appear also here!

		{:ok, rx2} = Reaxive.Rx.Impl.start("rx2", [auto_stop: false])
		Process.link(process rx2) #  just to ensure that failures appear also here!
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		{rx3, _disp_me} = Reaxive.Rx.Impl.subscribe(rx2, call_me)

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_next, :x}

		Reaxive.Rx.Impl.on_completed(rx1, self)
		id = process rx3
		assert_receive {:on_completed, ^id}

		assert Reaxive.Rx.Impl.subscribers(rx1) == []
		assert Reaxive.Rx.Impl.subscribers(rx2) == []
	end

	test "chaining two Rx streams with failures" do
		Process.flag(:trap_exit, true)
		{:ok, rx1} = Reaxive.Rx.Impl.start("chain 1", [auto_stop: false])
		Process.link(process rx1) #  just to ensure that failures appear also here!

		{:ok, rx2} = Reaxive.Rx.Impl.start("chain 2", [auto_stop: false])
		Process.link(process rx2) #  just to ensure that failures appear also here!
		:ok = Reaxive.Rx.Impl.fun(rx2, fn(_) -> 1/0 end) # will always fail
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		{rx3, _disp_me} = Reaxive.Rx.Impl.subscribe(rx2, call_me)
		id = process rx3

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
		dummy_sub = ReaxiveTestTools.EmptySubscription.new
		:ok = Reaxive.Rx.Impl.source(rx, {self, dummy_sub})
		{_, disp_me} = Reaxive.Rx.Impl.subscribe(rx, :me)
		{_, disp_you} = Reaxive.Rx.Impl.subscribe(rx, :you)

		assert Reaxive.Rx.Impl.subscribers(rx) == [:you, :me]

		Subscription.unsubscribe(disp_me)
		assert Reaxive.Rx.Impl.subscribers(rx) == [:you]
		Subscription.unsubscribe(disp_you)
		refute Process.alive?(process rx)
	end

	test "Stopping processes after completion" do
		{:ok, rx1} = Reaxive.Rx.Impl.start("rx1", [auto_stop: true])
		Process.link(process rx1) #  just to ensure that failures appear also here!

		{:ok, rx2} = Reaxive.Rx.Impl.start("rx2", [auto_stop: true])
		Process.link(process rx2) #  just to ensure that failures appear also here!
		src = Reaxive.Rx.Impl.subscribe(rx1, rx2)
		:ok = Reaxive.Rx.Impl.source(rx2, src)

		call_me = simple_observer_fun(self)
		{rx3, disp_me} = Reaxive.Rx.Impl.subscribe(rx2, call_me)
		id = process rx3

		assert Reaxive.Rx.Impl.subscribers(rx1) == [rx2]
		assert Reaxive.Rx.Impl.subscribers(rx2) == [call_me]

		Reaxive.Rx.Impl.on_next(rx1, :x)
		assert_receive {:on_next, :x}

		Reaxive.Rx.Impl.on_completed(rx1, self)
		assert_receive {:on_completed, ^id}
		Subscription.unsubscribe(disp_me) # we call this, because our functional observer is too stupid to do it by itself

		refute Process.alive?(process rx1)
		refute Process.alive?(process rx2)
	end

	@tag timeout: 1_000
	test "call the run callback" do
		me = self
		{:ok, rx} = Reaxive.Rx.Impl.start()

		dummy_sub = ReaxiveTestTools.EmptySubscription.new
		:ok = Reaxive.Rx.Impl.source(rx, {self, dummy_sub})

		Reaxive.Rx.Impl.on_run(rx, fn() -> send(me, :on_run_called) end)
		call_me = simple_observer_fun(self)
		{rx3, disp_me} = Reaxive.Rx.Impl.subscribe(rx, call_me)

		Runnable.run(rx)
		Observer.on_completed(rx, dummy_sub)

		assert_receive :on_run_called
		assert_receive {:on_completed, me}		
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

	defp process(%Rx_t{pid: pid}), do: pid	

end
