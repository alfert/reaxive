defmodule ReaxiveSubscriptionTest do
	use ExUnit.Case

	alias Reaxive.CompositeSubscription
	alias Reaxive.MultiAssignSubscription

	@tag timeout: 1_000
	test "simple unsubscribe" do
		me = self
		{:ok, sub} = Reaxive.Subscription.start_link(fn() -> unsubscribe("A", me) end)
		
		assert %Reaxive.Subscription{} = sub
		assert not (Subscription.is_unsubscribed?(sub))

		assert :ok == Subscription.unsubscribe(sub)
		assert Subscription.is_unsubscribed?(sub)
		assert_receive {:unsubscribe, "A"}

	end

	@tag timeout: 1_000
	test "composite Subscription Algebra" do
		me = self
		{:ok, subA} = Reaxive.Subscription.start_link(fn() -> unsubscribe("A", me) end)
		{:ok, subB} = CompositeSubscription.start_link(fn() -> unsubscribe("B", me) end)
		# IO.inspect subA
		# IO.inspect subB

		assert %Reaxive.Subscription{} = subA 
		assert not Subscription.is_unsubscribed?(subA)

		assert %Reaxive.CompositeSubscription{} = subB
		assert not Subscription.is_unsubscribed?(subB)

		subB |> CompositeSubscription.add(subA)
		assert not Subscription.is_unsubscribed?(subB)
		assert not Subscription.is_unsubscribed?(subA)

		assert :ok == Subscription.unsubscribe(subB)
		assert Subscription.is_unsubscribed?(subB)
		assert Subscription.is_unsubscribed?(subA)

		assert_receive {:unsubscribe, "B"}
		assert_receive {:unsubscribe, "A"}

		{:ok, subC} = Reaxive.Subscription.start_link(fn() -> unsubscribe("C", me) end)
		subB |> CompositeSubscription.add(subC)
		assert Subscription.is_unsubscribed?(subC)
		assert_receive {:unsubscribe, "C"}
	end

	@tag timeout: 1_000
	test "MultiAssign Subscription Algebra" do
		me = self
		{:ok, subA} = Reaxive.Subscription.start_link(fn() -> unsubscribe("A", me) end)
		{:ok, subB} = Reaxive.Subscription.start_link(fn() -> unsubscribe("B", me) end)
		# IO.inspect subA
		# IO.inspect subB

		assert %Reaxive.Subscription{} = subA 
		assert not Subscription.is_unsubscribed?(subA)

		assert %Reaxive.Subscription{} = subB
		assert not Subscription.is_unsubscribed?(subB)

		{:ok, multi} = MultiAssignSubscription.start_link(fn -> unsubscribe("multi", me) end)
		assert %MultiAssignSubscription{} = multi

		multi |> MultiAssignSubscription.assign(subA)
		multi |> MultiAssignSubscription.assign(subB)

		assert not Subscription.is_unsubscribed?(subB)
		assert not Subscription.is_unsubscribed?(subA)

		assert :ok == Subscription.unsubscribe(multi)
		assert Subscription.is_unsubscribed?(multi)
		assert Subscription.is_unsubscribed?(subB)
		assert not Subscription.is_unsubscribed?(subA)

		assert_receive {:unsubscribe, "B"}
		assert_receive {:unsubscribe, "multi"}

		{:ok, subC} = Reaxive.Subscription.start_link(fn() -> unsubscribe("C", me) end)

		multi |> MultiAssignSubscription.assign(subC)
		assert Subscription.is_unsubscribed?(subC)
		assert_receive {:unsubscribe, "C"}
	end

	def unsubscribe(name, pid) do
		# IO.puts "unsubcribe function for #{name}"
		send(pid, {:unsubscribe, name})
		:ok
	end


end
