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

end