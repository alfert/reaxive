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

end
