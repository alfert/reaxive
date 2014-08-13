defmodule RxTest do
	use ExUnit.Case
	import ReaxiveTestTools
	require Integer

	test "map function works" do
		value = 1
		{:ok, rx} = Reaxive.Rx.Impl.start()
		
		rx1 = rx |> Reaxive.Rx.map &(&1 + 1) 
		o = simple_observer_fun(self)
		rx2 = Observable.subscribe(rx1, o)

		assert Reaxive.Rx.Impl.subscribers(rx) == [rx1]
		assert Reaxive.Rx.Impl.subscribers(rx1) == [o]

		Reaxive.Rx.Impl.on_next(rx, 1)
		assert_receive {:on_next, 2}
		Reaxive.Rx.Impl.on_completed(rx)
		assert_receive {:on_completed, nil}
		Disposable.dispose(rx2)
		refute Process.alive?(rx)
	end

	test "map several values via |>" do
		{:ok, rx} = Reaxive.Rx.Impl.start()
		o = simple_observer_fun(self)

		rx2 = rx |> Reaxive.Rx.map(&(&1 + 1)) |> Observable.subscribe(o)

		Reaxive.Rx.Impl.on_next(rx, 1)
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
		values |> Reaxive.Rx.generate |> Observable.subscribe(o)
		
		values |> Enum.each fn(v) ->
			assert_receive{:on_next, ^v} end
		assert_receive {:on_completed, nil}
	end

	test "print out generated values" do
		values = [1, 2, 3, 4]
		values |> Reaxive.Rx.generate |> Reaxive.Rx.as_text
	end

	test "create a stream from a sequence of events" do
		values = 1..20 |> Enum.to_list
		l = values |> Reaxive.Rx.generate(1) |> 
			Reaxive.Rx.as_text |> Reaxive.Rx.stream |> Enum.to_list
		# l = s |> Enum.to_list
		assert values == l
	end

	test "abort a sequence early on via generate and stream" do
		all = 1..1000 |> Enum.to_list
		five = all |> Reaxive.Rx.generate(1) |>
			Reaxive.Rx.as_text |> Reaxive.Rx.stream |> Stream.take(5) |> Enum.to_list

		assert five == (all |> Enum.take(5))
	end

	test "filter out all odd numbers" do
		values = 1..20 |> Enum.to_list
		odds = values |> Reaxive.Rx.generate(1) |> Reaxive.Rx.filter(&Integer.odd?/1) |>
			 Reaxive.Rx.stream |> Enum.to_list

		assert Enum.all?(odds, &Integer.odd?/1)
		assert odds == (values |> Enum.filter(&Integer.odd?/1))
	end
end