defmodule RxTest do
	use ExUnit.Case
	import ReaxiveTestTools

	test "map function works" do
		value = 1
		{:ok, rx} = Reaxive.Rx.Impl.start()
		:ok = Reaxive.Rx.Impl.fun(rx, &identity/1) 

		rx1 = rx |> Reaxive.Rx.map &(&1 + 1) 
		o = simple_observer_fun(self)
		rx2 = Observable.subscribe(rx1, o)

		assert Reaxive.Rx.Impl.subscribers(rx) == [rx1]
		assert Reaxive.Rx.Impl.subscribers(rx1) == [o]

		# We need to implement the same chain from hand in rx_impl_test to ensure 
		# that our infrastructure works as expected.

		Reaxive.Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}
		Reaxive.Rx.Impl.on_completed(rx)
		assert_receive {:on_completed, nil}
		Disposable.dispose(rx2)
		refute Process.alive?(rx)
	end
end