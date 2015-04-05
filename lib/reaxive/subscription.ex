defmodule Reaxive.Subscription.State do
	@moduledoc """
	Encapsulates the internal state of subscriptions and implements all functions
	of the family of subscription (simple, composite, and multi-assign).
	"""

	defstruct active: true, # is the subscription active?
		dispose_fun: nil, # the function to call
		embedded_sub: nil # the embedded subscriptions

	@type t :: %__MODULE__{}

	def is_unsubscribed?(s = %__MODULE__{active: active}) do
		# IO.puts("#{__MODULE__}.is_unsubscribed?: s = #{inspect s}")
		active == :false
	end

	def start(disp_fun, embedded \\ nil), do: 
		%__MODULE__{active: true, dispose_fun: disp_fun, embedded_sub: embedded}

	@spec add(t, Subscription.t) :: t
	def add(s = %__MODULE__{embedded_sub: embedded, active: true}, sub) do
		%__MODULE__{s | embedded_sub: [sub] |> Enum.into embedded}
	end
	def add(s = %__MODULE__{embedded_sub: embedded}, sub) do
		:ok = Subscription.unsubscribe(sub)
		%__MODULE__{s | embedded_sub: [sub] |> Enum.into embedded}
	end
	
	@spec delete(t, Subscription.t) :: t
	def delete(s = %__MODULE__{embedded_sub: embedded}, sub) do
		%__MODULE__{s | embedded_sub: embedded |> Enum.reject(&(&1 == sub))}
	end

	@spec embedded(t) :: nil | Enumerable.t
	def embedded(%__MODULE__{embedded_sub: embedded}), do: embedded

	@spec assign(t, Subscription.t) :: t
	def assign(s = %__MODULE__{embedded_sub: _embedded, active: true}, sub) do
		%__MODULE__{s | embedded_sub: [sub]}
	end
	def assign(s = %__MODULE__{embedded_sub: _embedded}, sub) do
		:ok = Subscription.unsubscribe(sub)
		%__MODULE__{s | embedded_sub: [sub]}
	end

	@spec unsubscribe(t) :: {:ok, t}
	def unsubscribe(%__MODULE__{active: false} = s), do: {:ok, s}
	def unsubscribe(%__MODULE__{embedded_sub: nil, dispose_fun: disp} = s) do
		# IO.puts "active unsubscribe"
		:ok = disp.()
		{:ok, %__MODULE__{s | active: false}}
	end
	def unsubscribe(%__MODULE__{embedded_sub: embedded, dispose_fun: disp} = s) do
		:ok = disp.()
		embedded |> Enum.each fn(sub) -> :ok = Subscription.unsubscribe(sub) end
		{:ok, %__MODULE__{s | active: false}}
	end

	@doc """
	This macro allows the call to an GenServer. If the process does not exist, 
	then the default value is returned. 

	This macros is provided to implement subscriptions easier. 
	"""
	defmacro robust_call(default_value, do: block) do
		# block = Keyword.get(clause, :do)
		quote do
			try do
				unquote(block)
			catch
				:exit, {fail, {GenServer, :call, _}} when fail in [:normal, :noproc] ->
					IO.puts "subscription is already gone"
					unquote(default_value)
				:exit, :normal -> unquote(default_value)
			end
		end
	end


end

defmodule Reaxive.SubscriptionBehaviour do
	@moduledoc """
	Behaviour for subscriptions with default implementations which does not have any
	subelements. 

	It implements the protocol `Subscription`.
	"""
	use Behaviour

	@opaque t :: %{}
 
	defcallback start_link((()-> :ok)) :: t

	defcallback init((()-> :ok)) :: Reaxive.Subscription.State
	defcallback unsubscribe(t) :: :ok
	defcallback is_unsubscribed?(t) :: boolean  
	defcallback is_unsub?(t) :: boolean  


	@doc "Defines the default implementations of subscriptions"
	defmacro __using__(_opts) do
		quote do
			alias Reaxive.Subscription.State
			
			@typedoc "The type of a simple subscription"
			@opaque t :: %__MODULE__{}
			defstruct pid: nil 

			@spec start_link((()-> :ok)) :: t
			def start_link(disp_fun) do
				{:ok, pid} = Agent.start_link(fn() -> init(disp_fun) end)
				# IO.puts "start_link: #{inspect pid}"
				{:ok, %__MODULE__{pid: pid}}
			end

			def init(disp_fun), do: State.start(disp_fun) 

			@spec unsubscribe(t) :: :ok
			def unsubscribe(_sub = %__MODULE__{pid: pid}) do
				# IO.puts "unsubscribe"
				pid |> Agent.get_and_update(&State.unsubscribe/1)
			end
			
			def is_unsubscribed?(sub = %__MODULE__{pid: pid}) do
				# IO.puts "is_unsub: #{inspect sub}"
				try do 
					pid |> Agent.get(&State.is_unsubscribed?/1)
				catch 
					:exit, {fail, {GenServer, :call, _}} when fail in [:normal, :noproc] ->
						IO.puts "subscription is gone"
						true
				end
			end

			defoverridable [start_link: 1, unsubscribe: 1, is_unsubscribed?: 1, init: 1]
		end
	end	

end

defmodule Reaxive.Subscription do
	use Reaxive.SubscriptionBehaviour

	defimpl Subscription do
		def unsubscribe(sub), do: Reaxive.Subscription.unsubscribe(sub)
		def is_unsubscribed?(sub), do: Reaxive.Subscription.is_unsubscribed?(sub)
	end

end

defmodule Reaxive.CompositeSubscription do

	@moduledoc """
	Implements a  subscription which may have a list of 
	embedded subscriptions. If this outer subscription
	is unsubscribed, so are the inner subscriptions.  

	It implements the protocol `Subscription`.
	"""
	use Reaxive.SubscriptionBehaviour

	@spec init((()-> :ok)) :: State
	def init(disp_fun), do: State.start(disp_fun, [])
	
	@spec add(t, Subscription.t) :: t
	def add(sub= %__MODULE__{pid: pid}, to_add) do
		:ok = pid |> Agent.update(State, :add, [to_add])
		sub
	end

	@spec delete(t, Subscription.t) :: t
	def delete(sub= %__MODULE__{pid: pid}, to_delete) do
		:ok = pid |> Agent.update(State, :delete, [to_delete])
		sub
	end

	defimpl Subscription do
		def unsubscribe(sub), do: Reaxive.CompositeSubscription.unsubscribe(sub)
		def is_unsubscribed?(sub), do: Reaxive.CompositeSubscription.is_unsubscribed?(sub)
	end

end


defmodule Reaxive.MultiAssignSubscription do

	@moduledoc """
	Implements a subscription which may have an internal 
	subscription which is re-assignable. 

	If this outer subscription
	is unsubscribed, so are the inner subscriptions.  

	It implements the protocol `Subscription`.
	"""
	use Reaxive.SubscriptionBehaviour

	@spec init((()-> :ok)) :: State
	def init(disp_fun), do: State.start(disp_fun, [])
	
	@spec assign(t, Subscription.t) :: t
	def assign(sub= %__MODULE__{pid: pid}, to_add) do
		:ok = pid |> Agent.update(State, :assign, [to_add])
		sub
	end
	defimpl Subscription do
		def unsubscribe(sub), do: Reaxive.MultiAssignSubscription.unsubscribe(sub)
		def is_unsubscribed?(sub), do: Reaxive.MultiAssignSubscription.is_unsubscribed?(sub)
	end

end