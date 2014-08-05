defmodule Reaxive do
  use Application

# TODO:
# put this part into a separate file
# implement reactive streams as GenEvent Servers with lazy streams
# and see how it works!


  # See http://elixir-lang.org/docs/stable/Application.Behaviour.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Reaxive.Supervisor.start_link
  end

  @type signal :: Signal.t(any) # {:Signal, reference, pid, any}
  @type signal(a) :: Signal.t(a) # {:Signal, reference, pid, a}
  # @type sig_func(a, b) :: ((a, any) -> ({:reply, b, any} | {:noreply, any})) when a: var, b: var
  @type sig_func :: ((any, any) -> ({:reply, any, any} | {:noreply, any}))

  defmodule Signal do
    @derive Access
    defstruct id: nil, # id of the invividual sigal
      source: nil, # pid of the source 
      value: nil # current value of the signal

    @type t(a) :: %__MODULE__{id: nil|reference, source: nil|pid, value: nil | a} 
  end

  @doc """
  Implements the internal receive loop for a signal. 

  Its task is to manage the subscriptions of signals to which values are propagated. 
  Subscriptions are managed with `register`, `unregister` and `DOWN` messages. The 
  latter are created by monitoring signals and ensures that died signals are automatically
  unsubscribed, helping in both situations when nasty things happen and when signals do
  not know how to unsubscribe. 
  """
#  @spec signal_handler([{signal(a), reference}], sig_func, signal(b), any) :: no_return when a: var, b: var
  @spec signal_handler([{signal(any), reference}], sig_func, signal(any), any) :: no_return
  # def signal_handler(fun, signal), do: signal_handler([], fun, signal, nil)
  def signal_handler(subscriptions \\ [], fun, signal, state \\ nil) do
    receive do
      {:register, s = %Signal{}} ->
        log("register signal #{inspect s}")
        m = Process.monitor(s.source)
        signal_handler([{s, m} | subscriptions], fun, signal, state)
      {:unregister, s = %Signal{}} ->
        log("unregister signal #{inspect s}")
        signal_handler(subscriptions |> 
          Enum.reject(fn({sub, _mon}) -> sub.source == s.source end), fun, signal, state)
      {:DOWN, _m, :process, pid, reason} ->
        # a monitored Signal died, so take it out of the subscriptions
        log("got DOWN for process #{inspect pid} and reason #{inspect reason}")
        signal_handler(subscriptions |> 
          Enum.reject(fn({sub, _mon}) -> sub.source == pid end), fun, signal, state)
      msg = %Signal{}-> 
        log("got signal #{inspect msg}, calculating fun with value #{inspect msg.value} and state #{inspect state}")
        case fun . (msg.value, state) do
          {:reply, v, new_state} ->  
            s = %Signal{signal | id: :erlang.make_ref(), value: v}
            subscriptions |> Enum.each fn({sub, _m}) -> send(sub.source, s) end
            signal_handler(subscriptions, fun, signal, new_state)
          {:noreply, new_state} ->
            signal_handler(subscriptions, fun, signal, new_state)
        end
      any -> 
        log("got weird message #{inspect any}")
        %Signal{} = any
      end
  end

  @doc """
  Functional pushing of signals without any state interaction.
  """
  # @spec push((a) -> b) :: sig_func(a,b)
  def push(fun) do
    fn(a, state) -> 
      log "Pushing a =  #{inspect a} and state = #{inspect state}"
      v = fun . (a)
      {:reply, v, state} 
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
      :timer.send_interval(millis, %Signal{my_signal | value: :go})
      fun = fn(_v) -> 
        log "Got :go!"
        :os.timestamp() 
      end
      signal_handler(push(fun), %Signal{my_signal | source: self})
    end)
    %Signal{my_signal | source: p}
  end

  @doc """
  Function `lift` creates a new signal of type `b` by applying
  function `fun` to each value of `signal`, which has type `a`. 
  Consequently, function `fun` maps from type `a` to `b`.
  """
  @spec lift(signal(a), (a -> b)) :: signal(b) when a: var, b: var 
  def lift(signal = %Signal{}, fun) do
    my_signal = make_signal()
  	p = spawn(fn() -> 
      s = %Signal{my_signal | source: self}
      send(signal.source, {:register, s})
      signal_handler(push(fun), s)
    end)
    %Signal{my_signal | source: p}
  end
  
  @doc """
  Renders a signal as text. 
  """
  @spec as_text(signal|pid) :: :none # when a: var
  def as_text(s) when is_pid(s) do
    signal = make_signal
    as_text(%Signal{signal | source: s})
  end
  def as_text(signal = %Signal{}) do
    fun = fn(value) -> IO.inspect(value) end
    my_signal = make_signal()
    p = spawn(fn() -> 
      s = %Signal{my_signal | source: self}
      send(signal.source, {:register, s})
      signal_handler(push(fun), s)
    end)
    %Signal{my_signal | source: p}
  end


  @doc """
  Converts a signal in to regular lazy Elixir stream.
  """
  @spec as_stream(signal, pos_integer | :infinity) :: Enumerable.t
  def as_stream(signal = %Signal{}, timeout \\ :infinity) do
    # Register a signal process, which also reacts
    # on a `{:get, make_ref()}` message and answers with a 
    # `{:got, ref, value}`message. 
    # this signal process can have its own loop function
    #
    my_signal = make_signal()
    p = spawn(fn() -> 
      s = %Signal{my_signal | source: self}
      send(signal.source, {:register, s})
      stream_handler(s)
    end)
    sig = %Signal{my_signal | source: p}
    next_fun = fn(_acc) ->
      ref = make_ref()
      send(sig.source, {:get, ref, self})
      receive do
        {:got, ^ref, value} -> {value, :next}
        after timeout -> nil
      end
    end
    Stream.resource(
      fn() ->next_fun . (:next) |> elem(0) end, # lazy first value
      next_fun, # all other values
      fn(_) -> stop(sig) end # after termination
      )
  end
  
  def from_stream(s) do
    
  end
  


  def stream_handler(signal = %Signal{}) do
    receive do
      {:get, ref, pid} when is_reference(ref) and is_pid(pid) ->
        receive do 
          s = %Signal{} -> send(pid, {:got, ref, s.value})
        end
    end
    stream_handler(signal)
  end
  
  @spec filter(signal(a), (a -> boolean)) :: signal(a) when a: var
  def filter(signal = %Signal{}, pred) do
    # lift s, 
  end
  


  @doc """
  Creates a Signal where each item from the signal will be wrapped in a tuple alongside its index.

  Does not work yet!
  """
  def with_index(signal = %Signal{}) do
    # TODO correct implementation
    with = fn(v, i) -> {i + 1, v} end
    r = 1 .. :infinity
    # lift s, fn (v) -> 
    # with(v, 0)
    nil
  end
  

  @doc """
  Creates a new signal instance with optional `value`.
  """
  @spec make_signal(a) :: signal(a) when a: var
  def make_signal(value \\ nil) do
    %Signal{id: :erlang.make_ref(), source: self, value: value}
  end

  def log(msg) do
    IO.puts("#{inspect self}: #{inspect msg}")
  end  

  def stop(signal = %Signal{}) do
    log "Stopping signal #{inspect signal}"
    Process.exit(signal.source, :normal)
  end

  def test do
    m = every 1_000
    c = lift(m, fn(_) -> :toc end)
    as_text(c)
  end
  
  def test2 do
    m = every 1_000
    c = lift(m, fn(_) -> :toc end)
    s = as_stream(c)
    Stream.take(s, 5) |> Stream.with_index |> Enum.to_list
  end

  def test3 do
    m = every 1_000
    m |> lift(fn(_) -> :toc end) 
  end 

end
