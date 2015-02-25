defmodule Reaxive.Generator do
	@moduledoc """
	This module collects functions for generating a sequence of events. These generators 
	are always the roots of the event sequence network, they do not subscribe to other 
	sequences. However, often they use other data sources such a stream, an IO connection
	or the like. 

	Generators have the important feature of being canceable. This means that their generation 
	process can be canceled from the outside. This is important for freeing up any other 
	resources used the generator while producing new events. 
	"""

	require Logger

	@type accu_t :: any
	@typedoc "Generator function to be used by `Reaxive.Rx.delayed_start`"
	@type generator_fun_t :: ((Observable.t) -> any)

	@typedoc "Return value of producer functions for generators"
	@type rx_propagate :: {:on_next, any} | {:on_error, any} | {:on_completed, pid}

	@typedoc "Producer function without accu"
	@type producer_fun_t :: (() -> rx_propagate)
	@typedoc "Producer function with accu"
	@type producer_with_accu_fun_t :: ((accu_t) -> {accu_t, rx_propagate})

	@typedoc "The type of the abort function of a generator"
	@type aborter_t(u) :: (() -> u)

	@doc """
	Generates new values by calling `prod_fun` and sending them to `rx`. 
	If canceled (by receiving `:cancel`), the `abort_fun` is called. Between
	two events a `delay`, measured in milliseconds, takes place. 

	This function assumes an infinite generator. There is no means for finishing
	the generator except for canceling. 
	"""
	@spec generate(Observer.t, producer_fun_t, aborter_t(u), non_neg_integer) :: u when u: var
	def generate(rx, prod_fun, abort_fun, delay) do
		receive do
			:cancel -> abort_fun.()
		after 0 -> # if :cancel is not there, do not wait for it
			case prod_fun.() do
				{:on_next, event} -> 
					Observer.on_next(rx, event)
					:timer.sleep(delay)
					generate(rx, prod_fun, abort_fun, delay)
				{:on_error, error} -> 
					Observer.on_error(rx, error)
					abort_fun.()
				{:on_completed, _} -> 
					Observer.on_completed(rx, self)
					abort_fun.()
			end
		end
	end
	
	@doc """
	Generates new values by calling `prod_fun` and sending them to `rx`. 
	If canceled (by receiving `:cancel`), the `abort_fun` is called. Between
	two events a `delay`, measured in milliseconds, takes place. 

	This function assumes an infinite generator. There is no means for finishing
	the generator except for canceling. 
	"""
	@spec generate_with_accu(Observer.t, producer_with_accu_fun_t, aborter_t(u), accu_t, non_neg_integer) :: u when u: var
	def generate_with_accu(rx, prod_fun, abort_fun, accu, delay) do
		receive do
			:cancel -> abort_fun.()
		after 0 -> # if :cancel is not there, do not wait for it
			{new_accu, value} = prod_fun.(accu)
			case value do
				{:on_next, event} -> 
					Observer.on_next(rx, event)
					:timer.sleep(delay)
					generate_with_accu(rx, prod_fun, abort_fun, new_accu, delay)
				{:on_error, error} -> 
					Observer.on_error(rx, error)
					abort_fun.()
				{:on_completed, _} -> 
					Observer.on_completed(rx, self)
					abort_fun.()
			end
		end
	end

	#############
	### How to deal with 
	###   * finite generators, sending a on_complete after a while
	###   * generators with errors, sending on_error and finishing afterwards?
	### Both are required for IO-Generators!

	@doc """
	Sends a tick every `delay` milliseconds to `rx` 
	"""
	@spec ticks(non_neg_integer) :: generator_fun_t
	def ticks(delay) when delay >= 0, do:
		fn(rx) -> # Logger.info("tick process #{inspect self}")
			generate(rx, fn() -> {:on_next, :tick} end, 
				fn() -> # Logger.info("ticks stopped") 
					:ok end, 
				delay) end


	@doc """
	Enumerates the naturals number starting with `0`. Sends the 
	next number after `delay` milliseconds to `rx`. 
	"""
	@spec naturals(non_neg_integer) :: generator_fun_t
	def naturals(delay) when delay >= 0, do: 
		fn(rx) -> 
			generate_with_accu(rx, &({1+&1, {:on_next, &1}}), fn() -> :ok end, 0, delay) end

end