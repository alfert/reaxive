defmodule Reaxive do
  use Application.Behaviour

  # See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Reaxive.Supervisor.start_link
  end

  @type signal :: {:Signal, reference, pid, any}
  @type signal(a) :: {:Signal, reference, pid, a}

  defrecord Signal, 
  	id: nil, # id of the invividual sigal
  	source: nil, # pid of the source 
  	value: nil # current value of the signal

  @spec signal_handler([signal(a)], [reference], ((a) -> b), signal(b)) :: no_return when a: var, b: var
  def signal_handler(fun, signal), do: signal_handler([], [], fun, signal)
  def signal_handler(subscriptions, mons, fun, signal) do
    receive do
      {:register, s = Signal[]} ->
        m = Process.monitor(s.source)
        signal_handler([s | subscriptions], [m | mons], fun, signal)
      {:unregister, s = Signal[]} ->
        # TODO: for demonitoring, the mon ref must be known. put it to the signal list (pairs?)
        signal_handler(subscriptions |> Enum.reject(&(&1.source == s.source)), mons, fun, signal)
      {:DOWN, m, :process, pid, reason} ->
        # a monitored Signal died, so take it out of the subscriptions
        signal_handler(subscriptions |> Enum.reject(&(&1.source == pid)), 
            mons |> Enum.reject(&(&1 == m)), fun, signal)
      msg -> 
        v = fun . (msg)
        s = signal.update(id: :erlang.make_ref(), value: v)
        subscriptions |> Enum.each &(send(&1.source, s))
        signal_handler(subscriptions, mons, fun, signal)
      end
  end
  

  @doc """
  Function `every` is an input signal, i.e. it generates new signal values
  in an asynchronous manner. As an input signal is does not rely an any other
  signals, it is a root in dependency graph of signals.
  """
  @spec every(integer) :: signal(integer)
  def every(millis) do
    my_signal = make_signal()
    p = spawn(fn() -> 
      :timer.send_interval(millis, :go)
      fun = fn(_v) -> :os.timestamp() end
      signal_handler(fun, my_signal.update(source: self))
    end)
    my_signal.update(source: p)
  end

  @doc """
  Function `lift` creates a new signal of type `b` by applying
  function `fun` to each value of `signal`, which has type `a`. 
  Consequently, function `fun` maps from type `a` to `b`.
  """
  @spec lift((a -> b), signal(a)) :: signal(b) when a: var, b: var 
  def lift(fun, signal = Signal[]) do
    my_signal = make_signal()
  	p = spawn(fn() -> 
      send(signal.source, {:register, my_signal})
      signal_handler(fun, my_signal.update(source: p))
    end)
    my_signal.update(source: p)
  end
  
  @doc """
  Renders a signal as text. 
  """
  @spec as_text(signal|pid) :: :none # when a: var
  def as_text(s) when is_pid(s) do
    signal = make_signal
    as_text(signal.update(source: s))
  end
  def as_text(signal = Signal[]) do
    fun = fn(value) -> IO.inspect(value) end
    my_signal = make_signal()
    p = spawn(fn() -> 
      send(signal.source, {:register, my_signal})
      signal_handler(fun, my_signal.update(source: self))
    end)
    my_signal.update(source: p)
  end
  
  
  @doc """
  Creates a new signal instance with optional `value`.
  """
  @spec make_signal(a) :: signal(a) when a: var
  def make_signal(value \\ nil) do
    Signal.new(id: :erlang.make_ref(), source: self, value: value)
  end

  def log(msg) do
    IO.puts(msg)
  end  

  def stop(signal = Signal[]) do
    Process.exit(signal.source, :normal)
  end

end
