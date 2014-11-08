defmodule ReaxiveLazyTest do
	use ExUnit.Case
	import ReaxiveTestTools

	require Reaxive.Rx, as: Rx

	test "sequence of functions" do
		assert 12 == Rx.eval(5 |> inc |> double)
	end

	test "lazy simple function" do
		y = Rx.lazy(5 |> inc)
		assert %{} = y
		assert %Rx.Lazy{} = y
		assert 6 = Rx.eval(y)
	end

	test "lazy concat" do
		IO.puts "What is applied in y?"
		y = Rx.lazy(5 |> p |> inc)
		assert %{} = y
		IO.puts "You should not know that y contains applications of 5 "
		assert 6 = Rx.eval(y)
	end

	test "lazy do block" do
		y = Rx.lazy do 
			5 |> p |> inc |> p |> double
		end
		IO.inspect y
		assert %{} = y
		IO.puts "You should not know that y contains applications of 5 "
		assert 12 = Rx.eval(y)
	end

	test "lay Rx is evaluated" do
		rx1 = Rx.never
		assert %Rx.Lazy{} = rx1
		o = simple_observer_fun(self)
		rx2 = Observable.subscribe(rx1, o)

		refute_receive {:on_completed, x}
		Disposable.dispose(rx2)
	end


	test "lazy Rx" do
		l = [:no_value_assigned]
		r = [1, 2, 3] |> Rx.generate
		assert %Rx.Lazy{} = r
		# How do find out, which functions are called and which message are passed
		# between all the Rx.Impls?
		l = r |> Rx.stream |> Enum.to_list
		assert l == [1, 2, 3]
	end

end