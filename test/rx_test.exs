defmodule RxTest do
	use ExUnit.Case
	import ReaxiveTestTools
	require Integer
	alias Reaxive.Rx

	require Logger

	# one 1 second instead of 30 seconds
	@tag timeout: 1_000

	test "map function works" do
		{:ok, rx} = Rx.Impl.start()
		
		rx1 = rx |> Rx.map &(&1 + 1) 
		o = simple_observer_fun(self)
		rx2 = Observable.subscribe(rx1, o)

		#Rx.Impl.subscribers(rx) |> 
		#	Enum.each(fn(r) -> assert is_pid(r)end)
		# TODO: find a way to check the intended condition
		assert Rx.Impl.subscribers(rx1) == [o]

		Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}
		Rx.Impl.on_completed(rx)
		assert_receive {:on_completed, nil}
		Disposable.dispose(rx2)
		refute Process.alive?(rx)
	end

	test "map several values via |>" do
		proc_list = Process.list
		{:ok, rx} = Rx.Impl.start()
		o = simple_observer_fun(self)

		rx2 = rx |> Rx.map(&(&1 + 1)) 
		rx3 = rx2 |> Observable.subscribe(o)

		Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}

		Observer.on_next(rx, 2)
		assert_receive {:on_next, 3}

		values = [1, 2, 3, 4]
		values |> Enum.each fn(v) -> 
			Observer.on_next(rx, v) 
			k = v+1
			assert_receive {:on_next, ^k} 
		end
		Observer.on_completed(rx)
		assert_receive {:on_completed, nil}
		
		Disposable.dispose(rx3)

		assert process_leak?(proc_list)
	end

	test "generate some values" do
		values = [1, 2, 3, 4]
		o = simple_observer_fun(self)
		all_procs = Process.list()
		disp_me = values |> Rx.generate(1) |> Observable.subscribe(o)

		values |> Enum.each fn(v) ->
			assert_receive{:on_next, ^v} end
		assert_receive {:on_completed, nil}
		Disposable.dispose(disp_me)
		assert process_leak?(all_procs)
	end

	test "print out generated values" do
		values = [1, 2, 3, 4]
		o = simple_observer_fun(self)
		all_procs = Process.list()
		rxs = values |> Rx.generate(1) |> Rx.as_text 
		assert is_pid(rxs)
		disp_me =  rxs |> Observable.subscribe(o)
		assert_receive {:on_completed, nil}

		Disposable.dispose(disp_me)
		assert process_leak?(all_procs)
	end

	test "create a stream from a sequence of events" do
		values = 1..20
		l = values |> Rx.generate(1) |> 
			# Rx.as_text |> 
			Rx.stream |> Enum.to_list
		# l = s |> Enum.to_list
		assert Enum.to_list(values) == l
	end

	test "map a stream from a sequence of events" do
		values = 1..20
		l = values |> Rx.generate(1) |> 
			# Rx.as_text |> 
			Rx.map(&(&1+1)) |>
			Rx.stream |> Enum.to_list
		assert Enum.to_list(values)|>Enum.map(&(&1+1)) == l
	end

	test "abort a sequence early on via generate and stream" do
		all = 1..1000
		five = all |> Rx.generate(1) |>
			Rx.as_text |> Rx.stream |> Stream.take(5) |> Enum.to_list

		assert five == (all |> Enum.take(5))
	end

	test "filter out all odd numbers" do
		values = 1..20 
		odds = values |> Rx.generate(1) |> Rx.filter(&Integer.is_odd/1) |>
			 Rx.stream |> Enum.to_list

		assert odds == (values |> Enum.filter(&Integer.is_odd/1))
		assert Enum.all?(odds, &Integer.is_odd/1)
	end

	test "map and filter compose together" do
		values = 1..20 
		odds = values |> Rx.generate(1) |> Rx.filter(&Integer.is_odd/1) |>
			Rx.map(&inc/1) |> Rx.map(&inc/1) |> Rx.stream |> Enum.to_list

		assert odds == (values |> Enum.filter(&Integer.is_odd/1) |> Enum.map(&inc/1) |> Enum.map(&inc/1))
		assert Enum.all?(odds, &Integer.is_odd/1)
	end

	test "fold the past" do 
		values = 1..10

		f = fn
			({:on_next, event}, accu)           -> {:cont, {:on_next, accu + event}, accu + event}
			({:on_completed, _event} = e, accu) -> {:cont, e, accu}
		end
		{:ok, sum} = values |> Rx.generate(1) |> Rx.reduce(0, f) |> Rx.stream |> 
			Stream.take(-1) |> Enum.fetch(0)

		assert sum == Enum.sum(values)
	end

	test "take 5" do
		all = 1..1000
		five = all |> Rx.generate(1) |>
			Rx.take(5) |> Rx.stream  |> Enum.to_list

		assert five == (all |> Enum.take(5))
	end

	test "First of all" do
		values = 1..10
		first = values |> Rx.generate(1) |> Rx.first

		assert first == 1
	end

	test "sum it up" do
		values = 1..10
		sum = values |> Rx.generate(1) |> Rx.sum

		assert sum == Enum.sum(values)
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
		disp_me = error |> Observable.subscribe(o)
		assert_receive {:on_error, ^exception}
		disp_me.()
		# refute Process.alive?(error)
		process_leak?(all_procs)
	end

	test "handle errors within a stream" do 
		o = simple_observer_fun(self)
		all_procs = Process.list()
		all = Rx.error(RuntimeError.exception("check it out man")) |> Rx.stream |> Enum.to_list
		assert all == []
		assert process_leak?(all_procs)		
	end

	test "starts with a few numbers" do
		first = 1..10
		second = 11..20
		all = second |> Rx.generate(1) |> Rx.start_with(first) |>
			Rx.as_text |> 
			Rx.stream |> Enum.to_list

		assert Enum.concat(first, second) == all
	end

	test "merge a pair of streams" do
		first = 1..10
		second = 11..20
		first_rx = first |> Rx.generate(50) 
		second_rx = second |> Rx.generate(100)
		all = Rx.merge(first_rx, second_rx) |> 
			Rx.as_text |>
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
			Rx.as_text |>
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
			Rx.as_text |>
			Rx.stream |> Enum.sort

		assert [] == all
		refute Process.alive?(first_rx)
		refute Process.alive?(second_rx)
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
	
end