defmodule ReaxiveTest do
	use ExUnit.Case

	test "subscribe and dispose" do
		{:ok, rx} = Reaxive.Rx.start()
		disp_me = Reaxive.Rx.subscribe(rx, :me)
		disp_you = Reaxive.Rx.subscribe(rx, :you)

		assert Reaxive.Rx.subscribers(rx) == [:you, :me]

		Disposable.dispose(disp_me)
		assert Reaxive.Rx.subscribers(rx) == [:you]
	end
end
