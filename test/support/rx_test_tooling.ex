	defmodule ReaxiveTestTools.EmptySubscription do
		@moduledoc """
		This subscription does nothing. It is always unsubscribed 
		and requires no running process. 
		"""
		defstruct pid: self()

		def new, do: %__MODULE__{}

		defimpl Subscription do
			def unsubscribe(_sub), do: :ok
			def is_unsubscribed?(_sub), do: true
		end

		defimpl Runnable do
		  def run(_), do: :ok
		end
	end
