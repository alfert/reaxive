defmodule RxTest do
	use ExUnit.Case
	import ReaxiveTestTools
	require Integer
	require Reaxive.Rx, as: Rx

	require Logger

	test "map function works" do
		{:ok, rx} = Rx.Impl.start()
		
		rx1 = rx |> Rx.map &(&1 + 1) 
		o = simple_observer_fun(self)
		rx2 = Observable.subscribe(rx1, o)

		assert Rx.Impl.subscribers(rx) == [rx1]
		assert Rx.Impl.subscribers(rx1) == [o]

		Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}
		Rx.Impl.on_completed(rx)
		assert_receive {:on_completed, nil}
		Disposable.dispose(rx2)
		refute Process.alive?(rx)
	end

	test "map several values via |>" do
		{:ok, rx} = Rx.Impl.start()
		o = simple_observer_fun(self)

		rx2 = rx |> Rx.map(&(&1 + 1)) |> Observable.subscribe(o)

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
		
		Disposable.dispose(rx2)
		refute Process.alive?(rx)
	end

	test "generate some values" do
		values = [1, 2, 3, 4]
		o = simple_observer_fun(self)
		list1 = Process.list()
		values |> Rx.generate |> Observable.subscribe(o)

		values |> Enum.each fn(v) ->
			assert_receive{:on_next, ^v} end
		assert_receive {:on_completed, nil}
		list2 = Process.list()
		new_procs = Enum.reject(list2, &Enum.member?(list1, &1))
		refute new_procs == []
		assert length(new_procs) == 1
		assert Reaxive.Rx.Impl.subscribers(hd new_procs) == []
		Logger.error "Leak: Generator is still running."
	end

	test "print out generated values" do
		values = [1, 2, 3, 4]
		values |> Rx.generate |> Rx.as_text
	end

	test "create a stream from a sequence of events" do
		values = 1..20
		l = values |> Rx.generate(1) |> 
			Rx.as_text |> Rx.stream |> Enum.to_list
		# l = s |> Enum.to_list
		assert Enum.to_list(values) == l
	end

	test "abort a sequence early on via generate and stream" do
		all = 1..1000
		five = all |> Rx.generate(1) |>
			Rx.as_text |> Rx.stream |> Stream.take(5) |> Enum.to_list

		assert five == (all |> Enum.take(5))
	end

	test "filter out all odd numbers" do
		values = 1..20 
		odds = values |> Rx.generate(1) |> Rx.filter(&Integer.odd?/1) |>
			 Rx.stream |> Enum.to_list

		assert odds == (values |> Enum.filter(&Integer.odd?/1))
		assert Enum.all?(odds, &Integer.odd?/1)
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
end