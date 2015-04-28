defmodule Reaxive do
    use Application

    def start(_type, _args) do
        Reaxive.Supervisor.start_link
    end
    
end
