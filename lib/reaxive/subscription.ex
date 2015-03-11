defmodule Reaxive.Subscription.State do
	@moduledoc """
	Encapsulates the internal state of subscriptions and implements all functions
	of the family of subscription (simple, composite, and multi-assign).
	"""

	defstruct active: true, # is the subscription active?
		dispose_fun: nil, # the function to call
		embedded_sub: nil # the embedded subscriptions

	@type t :: %__MODULE__{}

	def is_unsubscribed?(%__MODULE__{active: active}), do: active == :false

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
		%__MODULE__{s | embedded_sub: sub}
	end
	def assign(s = %__MODULE__{embedded_sub: _embedded}, sub) do
		:ok = Subscription.unsubscribe(sub)
		%__MODULE__{s | embedded_sub: sub}
	end

	@spec unsubscribe(t) :: {:ok, t}
	def unsubscribe(%__MODULE__{active: false} = s), do: {:ok, s}
	def unsubscribe(%__MODULE__{embedded_sub: nil, dispose_fun: disp} = s) do
		:ok = disp.()
		{:ok, %__MODULE__{s | active: false}}
	end
	def unsubscribe(%__MODULE__{embedded_sub: embedded, dispose_fun: disp} = s) do
		:ok = disp.()
		embedded |> Enum.each fn(sub) -> :ok = Subscription.unsubscribe(sub) end
		{:ok, %__MODULE__{s | active: false}}
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
				{:ok, %__MODULE__{pid: pid}}
			end

			def init(disp_fun), do: State.start(disp_fun) 

			@spec unsubscribe(t) :: :ok
			def unsubscribe(_sub = %__MODULE__{pid: pid}) do
				pid |> Agent.get_and_update(State.unsubscribe/1)
			end
			
			def is_unsubscribed?(_sub = %__MODULE__{pid: pid}) do
				pid |> Agent.get(State.is_unsubscribed?/1)
			end
			
			defimpl Subscription do
				def unsubscribe(sub), do: __MODULE__.unsubscribe(sub)
				def is_unsubscribed?(sub), do: __MODULE__.is_unsubscribed(sub)
			end

			defoverridable [start_link: 1, unsubscribe: 1, is_unsubscribed?: 1, init: 1]
		end
	end	

end

defmodule Reaxive.Subscription do
	use Reaxive.SubscriptionBehaviour
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
end