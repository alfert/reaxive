defmodule Reaxive do
  use Application.Behaviour

  # See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Reaxive.Supervisor.start_link
  end

  @type signal(a) :: {:Signal, reference, pid, a}

  defrecord Signal, 
  	id: nil, # id of the invividual sigal
  	source: nil, # pid of the source 
  	value: nil # current value of the signal

  @spec signal_handler([signal(a)], ((a) -> b), signal(b)) :: no_return when a: var, b: var
  def signal_handler(subscriptions, fun, signal) do
    receive do
      {:register, s = Signal[]} ->
        signal_handler([s | subscriptions], fun, signal)
      {:unregister, s = Signal[]} ->
        signal_handler(subscriptions |> Enum.reject(&(&1.source == s.source)), fun, signal)
      msg -> 
        v = fun . (msg)
        s = signal.update(id: :erlang.make_ref(), value: v)
        subscriptions |> Enum.each &(send(&1, s))
      end
  end
  

  @doc """
  Function `every` is an input signal, i.e. it generates new signal values
  in an asynchronous manner. As an input signal is does not rely an any other
  signals, it is a root in dependency graph of signals.
  """
  @spec every(integer) :: signal(integer)
  def every(millis) do
    spawn(fn() -> 
      :timer.send_interval(millis, :go)
      my_signal = make_signal()
      fun = &:os.timstamp/0
      signal_handler([], fun, my_signal)
    end)
  end

  @doc """
  Function `lift` creates a new signal of type `b` by applying
  function `fun` to each value of `signal`, which has type `a`. 
  Consequently, function `fun` maps from type `a` to `b`.
  """
  @spec lift((a -> b), signal(a)) :: signal(b) when a: var, b: var 
  def lift(fun, signal = Signal[]) do
  	spawn(fn() -> 
      my_signal = make_signal()
      send(signal.source, {:register, my_signal})
      signal_handler([], fun, my_signal)
    end)
  end
  
  
  @doc """
  Creates a new signal instance with optional `value`.
  """
  @spec make_signal(a) :: signal(a) when a: var
  def make_signal(value \\ nil) do
    Signal.new(id: :erlang.make_ref(), source: self, value: value)
  end
  

end
