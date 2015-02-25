defmodule RxTest do
	use ExUnit.Case
	import ReaxiveTestTools
	require Integer
	alias Reaxive.Rx
	alias Reaxive.Rx.Impl.Rx_t

	require Logger

	# wait for messages passing through is 1 milli second
	@delay 1

	# one 1 second instead of 30 seconds
	@tag timeout: 1_000

	test "map function works" do
		{:ok, rx} = Rx.Impl.start()

		rx1 = rx |> Rx.map &(&1 + 1)
		o = simple_observer_fun(self)
		{id, disp_me} = Observable.subscribe(rx1, o)

		#Rx.Impl.subscribers(rx) |>
		#	Enum.each(fn(r) -> assert is_pid(r)end)
		# TODO: find a way to check the intended condition
		assert Rx.Impl.subscribers(rx1) == [o]

		Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}, @delay
		Rx.Impl.on_completed(rx, self)
		pid = process(id)
		assert_receive {:on_completed, ^pid}, @delay
		Disposable.dispose(disp_me)
		refute Process.alive?(process rx)
	end

	test "map several values via |>" do
		proc_list = Process.list
		{:ok, rx} = Rx.Impl.start()
		o = simple_observer_fun(self)
		Rx.Impl.source(rx, {self, fn() -> :ok end})

		rx2 = rx |> Rx.map(&(&1 + 1))
		{rx3, disp_me} = rx2 |> Observable.subscribe(o)

		Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}, @delay

		Observer.on_next(rx, 2)
		assert_receive {:on_next, 3}, @delay

		values = [1, 2, 3, 4]
		values |> Enum.each fn(v) ->
			Observer.on_next(rx, v)
			k = v+1
			assert_receive {:on_next, ^k}, @delay
		end
		Observer.on_completed(rx, self)
		id = process rx3
		assert_receive {:on_completed, ^id}, @delay

		Disposable.dispose(disp_me)

		assert process_leak?(proc_list)
	end

	test "generate some values" do
		values = [1, 2, 3, 4]
		o = simple_observer_fun(self)
		all_procs = Process.list()
		{rx, disp_me} = values |> Rx.generate |> Observable.subscribe(o)

		values |> Enum.each fn(v) ->
			assert_receive{:on_next, ^v}, @delay end
		id = process rx
		assert_receive {:on_completed, ^id}, @delay
		Disposable.dispose(disp_me)
		assert process_leak?(all_procs)
	end

	test "print out generated values" do
		values = [1, 2, 3, 4]
		o = simple_observer_fun(self)
		all_procs = Process.list()
		rxs = values |> Rx.generate |> Rx.as_text
		assert is_pid(process rxs)
		{rx, disp_me} =  rxs |> Observable.subscribe(o)
		# wait longer due to IO happening which might
		# change timings on travis and other CI platforms
		id = process rx
		assert_receive {:on_completed, ^id}

		Disposable.dispose(disp_me)
		assert process_leak?(all_procs)
	end

	test "create a stream from a sequence of events" do
		values = 1..20
		l = values |> Rx.generate |>
			# Rx.as_text |>
			Rx.stream |> Enum.to_list
		# l = s |> Enum.to_list
		assert Enum.to_list(values) == l
	end

	test "map a stream from a sequence of events" do
		values = 1..20
		l = values |> Rx.generate |>
			# Rx.as_text |>
			Rx.map(&(&1+1)) |>
			Rx.stream |> Enum.to_list
		assert Enum.to_list(values)|>Enum.map(&(&1+1)) == l
	end

	test "map a single valued sequence" do 
		five = Rx.return(3) |> # Rx.as_text |> 
			Rx.map(&(&1 + 2)) # |>  Rx.as_text 
		# Logger.info("five should be an Observable: #{inspect five}")
		five_scalar = five |> Rx.first
		# Logger.info("five scalar is #{inspect five_scalar}")
		assert  five_scalar == 5
	end

	test "abort a sequence early on via generate and stream" do
		all = 1..1000
		five = all |> Rx.generate |>
			# Rx.as_text |> 
			Rx.stream |> Stream.take(5) |> Enum.to_list

		assert five == (all |> Enum.take(5))
	end

	test "filter out all odd numbers" do
		values = 1..20
		odds = values |> Rx.generate |> Rx.filter(&Integer.is_odd/1) |>
			 Rx.stream |> Enum.to_list

		assert odds == (values |> Enum.filter(&Integer.is_odd/1))
		assert Enum.all?(odds, &Integer.is_odd/1)
	end

	test "map and filter compose together" do
		values = 1..20
		odds = values |> Rx.generate |> Rx.filter(&Integer.is_odd/1) |>
			Rx.map(&inc/1) |> Rx.map(&inc/1) |> Rx.stream |> Enum.to_list

		assert odds == (values |> Enum.filter(&Integer.is_odd/1) |> Enum.map(&inc/1) |> Enum.map(&inc/1))
		assert Enum.all?(odds, &Integer.is_odd/1)
	end

	test "fold the past" do
		values = 1..10

		sum = values |> Rx.generate |>
			Rx.reduce(0, fn(x, acc) -> x + acc end) |>
			Rx.first

		assert sum == Enum.sum(values)
	end

	test "take 5" do
		all = 1..1000
		five = all |> Rx.generate |>
			Rx.take(5) |> Rx.stream  |> Enum.to_list

		assert five == (all |> Enum.take(5))
	end

	test "First of all" do
		values = 1..10
		first = values |> Rx.generate |> Rx.first

		assert first == 1
	end

	test "First of naturals" do
		first = Rx.naturals  |> Rx.drop(5) |> Rx.first

		assert first == 5
	end

	test "sum it up" do
		values = 1..10
		sum = values |> Rx.generate |> Rx.sum

		assert sum == Enum.sum(values)
	end

	test "sum it up with naturals" do
		sum5_9 = Rx.naturals  |> Rx.drop(5) |> Rx.take(5) |> Rx.sum
		assert sum5_9 == 5..9 |> Enum.sum
	end

	test "sum it up with naturals 2" do
		sum1_5 = Rx.naturals |> Rx.take(5) |> Rx.map(&(&1 +1)) |> Rx.sum
		assert sum1_5 == 1..5 |> Enum.sum
	end

	test "multiply it up" do
		values = 1..10
		product = values |> Rx.generate |> Rx.product

		assert product == Enum.reduce(values, 1, &*/2)
	end

	test "multiply it up with naturals" do
		prod1_5 = Rx.naturals |> Rx.take(5) |> Rx.map(&(&1 +1)) |> Rx.product
		assert prod1_5 == 120
	end


	test "never sends no events" do
		o = simple_observer_fun(self)
		Rx.never |> Observable.subscribe(o)
		refute_receive _, 500, "Rx.never has send a msg!"
	end

	test "error sends an exception and terminates" do
		exception = RuntimeError.exception("check it out man")
		all_procs = Process.list()
		o = simple_observer_fun(self)
		error = Rx.error(exception)
		{_id, disp_me} = error |> 
			# Rx.as_text |> 
			Observable.subscribe(o)
		assert_receive {:on_error, ^exception}, @delay
		disp_me.()
		# refute Process.alive?(error)
		process_leak?(all_procs)
	end

	test "handle errors within a stream" do
		_o = simple_observer_fun(self)
		all_procs = Process.list()
		all = Rx.error(RuntimeError.exception("check it out man")) |> Rx.stream |> Enum.to_list
		assert all == []
		assert process_leak?(all_procs)
	end

	test "starts with a few numbers" do
		first = 1..10
		second = 11..20
		all = second |> Rx.generate |> Rx.start_with(first) |>
			# Rx.as_text |>
			Rx.stream |> Enum.to_list

		assert Enum.concat(first, second) == all
	end

	test "merge a pair of streams" do
		first = 1..10
		second = 11..20
		first_rx = first |> Rx.generate(50)
		second_rx = second |> Rx.generate(100)
		all = Rx.merge(first_rx, second_rx) |>
			# Rx.as_text |>
			Rx.stream |> Enum.sort

		assert Enum.concat(first, second) == all
	end

	test "merge a triple of streams" do
		first = 1..10
		second = 11..20
		third = 21..30
		first_rx = first |> Rx.generate(50)
		second_rx = second |> Rx.generate(100)
		third_rx = third |> Rx.generate(75)
		all = Rx.merge([first_rx, second_rx, third_rx]) |>
			# Rx.as_text |>
			Rx.stream |> Enum.sort

		assert Enum.concat([first, second, third]) == all
	end

	# one 1 second instead of 30 seconds
	@tag timeout: 1_000
	test "merge streams with errors" do
		first = 1..10
		second = 11..20
		first_rx = first |> Rx.generate(50)
		second_rx = second |> Rx.generate(100)
		all = Rx.merge([first_rx, second_rx, Rx.error(RuntimeError.exception("check it out man"))]) |>
			# Rx.as_text |>
			Rx.stream |> Enum.sort

		assert [] == all
		refute Process.alive?(process first_rx)
		refute Process.alive?(process second_rx)
	end

	test "naturals are counting from zero" do
		hundreds = Rx.naturals() |> Rx.take(100) |> Rx.stream |> Enum.to_list
		assert hundreds == 0..99 |> Enum.to_list
	end

	test "distinct values are filtered out" do
		tens = Rx.naturals |> Rx.take(100) |> Rx.map(&(rem(&1, 10))) |>
			Rx.distinct() |> Rx.stream |> Enum.sort
		assert tens == 0..9 |> Enum.to_list
	end

	test "distinct values only" do
		tens = Rx.naturals |> Rx.take(100) |> Rx.map(&(div(&1, 10))) |>
			Rx.distinct() |> Rx.stream |> Enum.sort
		assert tens == 0..9 |> Enum.to_list
	end

	test "distinct values changes only" do
		input = [1, 1, 2, 1, 1, 0, 1, 2, 2, 3]
		filtered = input |> Rx.generate |>
			Rx.distinct_until_changed() |> Rx.stream |> Enum.to_list()
		assert filtered == [1, 2, 1, 0, 1, 2, 3]
	end

	test "distinct values changes only 2" do
		tens = Rx.naturals |> Rx.take(100) |> Rx.map(&(div(&1, 10))) |>
		Rx.distinct_until_changed() |> Rx.stream |> Enum.sort
		assert tens == 0..9 |> Enum.to_list
	end

	test "take_while takes ony while true" do
		tens = Rx.naturals |> Rx.take_while(&(&1 < 10)) |>
			Rx.stream |> Enum.sort
		assert tens == 0..9 |> Enum.to_list
	end

	test "take_until takes ony while false" do
		tens = Rx.naturals |> Rx.take_until(&(&1 > 10)) |>
			Rx.stream |> Enum.sort
		assert tens == 0..10 |> Enum.to_list
	end

	test "drop the first 10 elements" do
		nineties = Rx.naturals |> Rx.take(100) |> Rx.drop(10) |>
			Rx.stream |> Enum.to_list
		assert nineties == 10..99 |> Enum.to_list
	end

	test "drop_while drops ony while true" do
		tens = Rx.naturals |> Rx.take(100) |> Rx.take_while(&(&1 < 10)) |>
		Rx.stream |> Enum.to_list
		assert tens == 0..9 |> Enum.to_list
	end

	test "drop_while drops ony while true in a row" do
		twenty = 0..20 |> Enum.to_list
		tens = Rx.generate(twenty ++ twenty, 1) |> Rx.take_while(&(&1 < 10)) |>
		Rx.stream |> Enum.to_list
		assert tens == 0..9 |> Enum.to_list
	end

	test "all even numbers can be divided by two" do
		even = Rx.naturals |> Rx.take(10) |> Rx.map &(&1 * 2)

		assert (even |> Rx.all(&Integer.is_even/1)) == true
	end

	test "all odd numbers cannot be divided by two" do
		odds = Rx.naturals |> Rx.take(10) |> Rx.map &(1 + &1 * 2)

		assert (odds |> Rx.all(&Integer.is_even/1)) == false
	end

	test "any odd numbers cannot be divided by two" do
		odds = Rx.naturals |> Rx.take(10) |> Rx.map &(1 + &1 * 2)

		assert (odds |> Rx.any(&Integer.is_even/1)) == false
	end

	test "some odd number can be divided by seven" do
		odds = Rx.naturals |> Rx.take(10) |> Rx.map &(1 + &1 * 2)

		assert (odds |> Rx.any(&(rem(&1, 7) == 0))) == true
	end

	test "the empty sequence has no elements" do
		empty = Rx.empty() |> Rx.stream |> Enum.to_list
		assert [] == empty
	end

	test "returns means a single valued sequence" do
		one = Rx.return(1) |> 
			# Rx.as_text |> 
			Rx.stream |> Enum.to_list
		assert [1] == one
	end

	@tag timeout: 1_000
	test "a simple sequence generated by flat_map" do
		k = 10
		file = start_tracing()
		flatter = Rx.return(k) |> Rx.flat_map(&(Rx.generate(1..&1)))
		# Logger.info("flat_mapper is #{inspect flatter}")
		tens = flatter |>
			# Rx.as_text |>
			Rx.to_list
		stop_tracing(file)
		assert 1..k |> Enum.to_list == tens
	end

	@tag timeout: 1_000
	test "a more complex sequence generated by flat_map" do
		n = 10
		k = 1..n
		flatter = Rx.generate(k) |> Rx.flat_map(&(Rx.generate(1..&1)))
		# Logger.info("flatter is #{inspect flatter}")
		tens = flatter |>
			# Rx.as_text |>
			Rx.to_list
		assert Enum.count(tens) == div(n*(n+1), 2)
		assert k |> Enum.to_list == tens |> Enum.uniq
	end


	test "properly canceled ticks" do
		proc_list = Process.list
		k = 1
		# file = start_tracing()
		ticks = Rx.ticks |> Rx.take(k) |> Rx.to_list
		# stop_tracing(file)
		assert ticks == [:tick]|> Stream.cycle |>Enum.take(k)
		assert process_leak?(proc_list)
	end

	test "properly canceled naturals" do
		proc_list = Process.list
		k = 10
		naturals = Rx.naturals |> Rx.take(k) |> Rx.to_list
		assert naturals == 0..k|> Enum.take(k)
		assert process_leak?(proc_list)
	end

	@tag timeout: 2_000
	test "merge naturals" do
		# file = start_tracing()
		tens = Rx.naturals |> Rx.take(10)
		fives = Rx.naturals |> Rx.take(5)
		mergers = [tens, fives]
		l = mergers |> Rx.merge |> Rx.to_list |> Enum.sort
		# stop_tracing(file)
		assert l == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9]
	end	

	###############################################################
	## Helper functions

	def start_tracing() do
		# :dbg.tracer
		f = Reaxive.Trace.start()
		{:ok, _} = :dbg.tp(Reaxive.Rx, :cx)
		{:ok, _} = :dbg.tp(Reaxive.Sync, :cx)
		{:ok, _} = :dbg.tp(Reaxive.Generator, :cx)
		{:ok, _} = :dbg.tp(Reaxive.Rx.Impl, :cx)
		{:ok, _} = :dbg.tp(Enum, :cx)
		{:ok, _} = :dbg.tp(Stream, :cx)
		{:ok, _} = :dbg.p(:new, [:c, :sos])
		{:ok, _} = :dbg.p(:new, [:m, :sos])
		{:ok, _} = :dbg.p(self, [:p, :sos])
		:timer.sleep(50)	
		f	
	end
	
	def stop_tracing(nil), do: :ok
	def stop_tracing(f) do
		:timer.sleep(50)	
		:dbg.p(:all, :clear)
		Reaxive.Trace.stop(f)
	end
	

	def process_leak?(initial_processes, delay \\ 100) do
		:timer.sleep(delay)
		list2 = Process.list()
		new_procs = Enum.reject(list2, &Enum.member?(initial_processes, &1))
		if length(new_procs) > 0, do:
			new_procs |> Enum.each(fn (p) -> IO.inspect Process.info(p) end)
		assert new_procs == []
		true
	end

	defp process(%Rx_t{pid: pid}), do: pid	

end
