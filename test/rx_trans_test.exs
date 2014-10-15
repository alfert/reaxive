defmodule RxTransduceTest do
	use ExUnit.Case
	alias Reaxive.Transducer, as: Trans
	import ReaxiveTestTools		
	require Logger
	require Integer

	test "map a list" do 
		l = 1..20 |> Enum.to_list
		m = Trans.map(l, &inc/1)

		assert m == Enum.map(l, &inc/1)
	end

	test "filter a list" do
		l = 1..20 |> Enum.to_list
		m = Trans.filter(l, &Integer.is_odd/1)

		assert m == Enum.filter(l, &Integer.is_odd/1)
	end

	test "take_while a list" do
		l = 1..20 |> Enum.to_list
		p = &(&1 < 5)
		m = Trans.take_while(l, p)

		assert is_list(m)
		assert m == Enum.take_while(l, p)
	end

	test "map and filter" do
		l = 1..20 |> Enum.to_list

		# f = Trans.filtering(&Integer.is_odd/1)
		# m = Trans.mapping(&inc/1) 

		mf = Trans.mapped_filtering(&inc/1, &Integer.is_odd/1)
		m = Trans.transduce(l, mf) |> Enum.reverse

		assert m == l |> Enum.map(&inc/1) |> Enum.filter(&Integer.is_odd/1)
	end

	test "performance test transduce" do
		l = 1..1_000_000 |> Enum.to_list
		t = fn() -> l |> Enum.map(&inc/1) |> Enum.filter(&Integer.is_odd/1) end
		m = fn() -> 
			mf = Trans.mapped_filtering(&inc/1, &Integer.is_odd/1)
			Trans.transduce(l, mf) |> Enum.reverse
		end

		{dur_trans, v2} = :timer.tc(m)
		{dur_enum, v1} = :timer.tc(t)
		
		assert v1 == v2
		assert dur_trans < dur_enum
		assert dur_trans * 1.5 < dur_enum
	end

end