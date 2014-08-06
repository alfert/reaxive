defmodule Reaxive do
    use Application

    # TODO:
    # put this part into a separate file
    # implement reactive streams as GenEvent Servers with lazy streams
    # and see how it works!
    #
    # GENERAL PROBLEM:
    # Streams are pull-type lazy enumerations, reactive extensions are push-type lazy enumerations.
    # How do the fit together? How do we implement the push-type enumerations?


    def start(_type, _args) do
        Reaxive.Supervisor.start_link
    end

    def every(millis \\ 1_000, value \\ :toc) do
        # start an event server and push to him notify events
        # What is the return type? 
        #   - a Signal? should contain the stream id of the event server to cancel it properly


        # Send every `millis` milliseconds to process `generator` the value
        #    the generators feeds the value via notfiy_event to a GenEvent server
        #    but how do we cancel the calculation? ==> This is the idea of Eric Meijer
        # ~~> if we implement our own stream/Enum protocol than we could remove the handler
        #     after finishing a reduce operation. 
        # ~~> we could use linked handlers that are linked to the current process. If the current process
        #     dies, then the handler is removed automatically.
        #
        #############################
        # Other approach:
        #
        # Use Stream.resource for every() as shown in the Elixir book (p.100ff), don't use a timer but 
        # use timeouts of receive. Check for transitivity of canceled calculations and also for 
        # the ability to join parallel streams (I assume that something like Stream.zip should work)
        ############################# 
        id = :erlang.make_ref
        {:ok, gen_ev} = GenEvent.start_link(name: 
            {:global, "every_#{inspect millis}_#{inspect value}_#{inspect id}"})
        generator = spawn(fn() -> 
            f = fn(g) ->
                receive do
                    {:value, value} -> GenEvent.notify(gen_ev, value)
                end
                g.(g)
            end
            f.(f)
        end)
        :ok = GenEvent.add_handler(gen_ev, Reaxive.EventGenerator, generator)
        :timer.send_interval(millis, generator, {:value, value})
        GenEvent.stream(gen_ev, id: id)
    end
    
    def make_signal(id \\ :erlang.make_ref()) do
        
    end
    

    defmodule EventGenerator do
        @moduledoc """
        An EventHandler for event generators, i.e. for those event sources which are 
        the roots of the net of event sources.

        With this event handler is a process associated which generates the events. If this event 
        handler terminates, it stops also the event generator process. 
        """
        use GenEvent

        defstruct generator: nil

        def init(gen) when is_pid(gen), do: {:ok, %EventGenerator{generator: gen}}
        
        def handle_event(event, state) do
            IO.puts("#{__MODULE__}: got event #{inspect event}")
            {:ok, state}
        end
        

        def terminate(reason, %EventGenerator{generator: nil}), do: :ok
        def terminate(reason, %EventGenerator{generator: gen}) when is_pid(gen) do
            IO.puts "EventGenerator for #{inspect gen} is shutting down"
            Process.exit(gen, :kill)
        end
        
    end

      
end
