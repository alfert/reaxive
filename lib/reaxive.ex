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



      
end
