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
		r = 1..1_000_000
		l = r |> Enum.to_list
		t = fn() -> r |> Stream.map(&inc/1) |> Stream.filter(&Integer.is_odd/1) |> Enum.to_list end
		m = fn() -> 
			mf = Trans.mapped_filtering(&inc/1, &Integer.is_odd/1)
			r |> Trans.transduce(mf) 
		end


		{dur_trans, v2} = :timer.tc(m)
		{dur_enum, v1} = :timer.tc(t)
		
		assert v1 == v2  |> Enum.reverse
		assert dur_trans < dur_enum
		assert dur_trans * 1.5 < dur_enum
	end

	test "memory test transduce" do
		r = 1..1_000_000
		l = r |> Enum.to_list
		e = fn() -> r |> Enum.map(&inc/1) |> Enum.filter(&Integer.is_odd/1) |> Enum.to_list end
		t = fn() -> 
			mf = Trans.mapped_filtering(&inc/1, &Integer.is_odd/1)
			r |> Trans.transduce(mf) |> Enum.reverse
		end

		{r1, i1, f1} = memory_profiler(e)
		{r2, i2, f2} = memory_profiler(t)

		assert r1 == r2
		assert i1 == i2
		assert f1[:memory] > f2[:memory]
		assert f1[:total_heap_size] > f2[:total_heap_size]
	end

	def memory_profiler(fun) do
		l = [:memory, :total_heap_size, :heap_size]
		f = fn() -> 
			initial = :erlang.process_info(self, l) # Process.info(self, l)
			r = fun.()
			final = :erlang.process_info(self, l) # Process.info(self, l)
			{r, initial, final}
		end
		Task.await(Task.async(f))
	end

end