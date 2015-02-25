defmodule Reaxive do
    use Application

    def start(_type, _args) do
        Reaxive.Supervisor.start_link
    end
   
    def test_ping do
        ponger = spawn(fn() -> ponger(3) end)
        me = self
        spawn(fn() -> 
            pinger(ponger) 
            send(me, :stop)
        end)
        receive do
            :stop -> 1# IO.puts "Stoppped"
        end
    end
    
    def pinger(ponger) do
        receive do
            :cancel -> 1 # IO.puts ("Canceled")
        after 0 -> 
            send(ponger, {:ping, self})
            pinger(ponger)
        end
        
    end

    def ponger(0) do
        receive do
            {:ping, pid} ->
                # IO.puts "got :ping, send :cancel"
                send(pid, :cancel)
        end
    end 
    def ponger(n) do
        receive do
            {:ping, _pid} -> 
                # IO.puts "got :ping"
                ponger (n-1)
        end
    end
    

    def test do
    	alias Reaxive.Rx
    	tens = Rx.naturals(1) |> Rx.take(2)
		mergers = [tens]
		l = mergers |> Rx.merge |> Rx.to_list |> Enum.sort
		# stop_tracing(file)
		#if (l == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9]),
		#	do: IO.puts("yeah"), else: IO.puts("ney")
    end
    
    def test_with_2 do
        alias Reaxive.Rx
        tens = Rx.naturals(1) |> Rx.take(10)
        fives = Rx.naturals(1) |> Rx.take(5)
        mergers = [tens, fives]
        l = mergers |> Rx.merge |> Rx.to_list |> Enum.sort
        # stop_tracing(file)
        if (l == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9]),
            do: IO.puts("yeah"), else: IO.puts("ney")
    end
    
end
