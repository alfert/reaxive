defmodule RxTransduceTest do
	use ExUnit.Case
	alias Reaxive.Transducer, as: Trans
	import ReaxiveTestTools		
	require Logger

	test "map a list" do 
		l = 1..20 |> Enum.to_list
		m = Trans.map(l, &inc/1)

		assert m == Enum.map(l, &inc/1)
	end
end