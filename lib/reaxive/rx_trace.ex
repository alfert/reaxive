defmodule Reaxive.Trace do
	@moduledoc """
	This module provides some convenience functions for tracing. It uses the `dbg` module from 
	Erlang to receive relevant messages. 
	"""
	require Logger

	def handler(message, acc = [trace_file]) do
		# Logger.info("Reaxive.Trace.handler: #{format(message)}")
		IO.puts(trace_file, format(message))
		acc
	end
	
	def start() do
		File.mkdir_p! "trace"
		{:ok, trace_file} = File.open("trace/trace.euml", [:write])
		IO.puts(trace_file, "@startuml")
		# the self process is the first participant in the diagram 
		# to order the participants properly
		IO.puts(trace_file, "participant \"#{inspect self}\"")
		{:ok, pid} = :dbg.tracer(:process, {&handler/2, [trace_file]})
		trace_file
	end
	
	def stop(trace_file) do
		IO.puts(trace_file, "@enduml")
		File.close(trace_file)
	end
	

	def format(%Reaxive.Rx.Impl{name: name, subscribers: subscribers, sources: sources}), do:
		"%Reaxive.Rx.Impl{#{name}, sub: #{inspect subscribers}, src: #{inspect sources}"
	def format({:trace, source, :call, {mod, fun, args}}) do
		arg_string = args |> Enum.map(&("#{format &1}")) |> Enum.join(",\\n")
		"""
		\"#{inspect source}\" -> \"#{inspect source}\": call #{inspect mod}.#{inspect fun}(#{arg_string})
		activate \"#{inspect source}\"
		"""
	end
	def format({:trace, source, :call, {mod, fun, args}, any}) do
		arg_string = args |> Enum.map(&("#{format &1}")) |> Enum.join(",")
		"""
		\"#{inspect source}\" -> \"#{inspect source}\": call #{inspect mod}.#{inspect fun}(#{arg_string}) Context: #{inspect any}
		activate \"#{inspect source}\"
		"""
	end
	def format({:trace, source, :return_from, {m, f, a}, {:reply, ret, state}}), do:
		"""
		\"#{inspect source}\" --> \"#{inspect source}\": return #{inspect m}.#{inspect f}/#{a}: \\n{#{:reply}, #{format(ret)},\\n #{format state}}
		deactivate \"#{inspect source}\"
		"""
	def format({:trace, source, :return_from, {m, f, a}, {:noreply, state}}), do:
		"""
		\"#{inspect source}\" --> \"#{inspect source}\": return #{inspect m}.#{inspect f}/#{a}: \\n{#{:noreply},\\n #{format state}}
		deactivate \"#{inspect source}\"
		"""
	def format({:trace, source, :return_from, {m, f, a}, reply}), do:
		"""
		\"#{inspect source}\" --> \"#{inspect source}\": return #{inspect m}.#{inspect f}/#{a}: \\n#{format reply}
		deactivate \"#{inspect source}\"
		"""
	def format({:trace, src, :send, msg, :code_server}=m), do: "' ignore messages to the codeserver #{inspect m}"
	def format({:trace, src, :send, msg, :init}=m), do: "' ignore messages to init #{inspect m}"
	def format({:trace, source, :send, msg, target}), do:
		"\"#{inspect source}\" -> \"#{inspect target}\": #{inspect msg}"
	def format({:trace, source, :send_to_non_existing_process, msg, target}), do:
		"""
		destroy \"#{inspect target}\"
		\"#{inspect source}\" ->x \"#{inspect target}\": #{inspect msg}
		"""
	def format({:trace, src, :spawn, target, 
		{:proc_lib, :init_p, [src, [], :gen, :init_it, 
			[:gen_server, src, :self, Reaxive.Rx.Impl, args, []]]}}), do: 
		"""
		' participant \"Reaxive.Rx.Impl:#{hd args}\" as \"#{inspect target}\"
		create \"#{inspect target}\"
		\"#{inspect src}\" -> \"#{inspect target}\": spawn Reaxive.Rx.Impl.init(#{inspect args}) 
		activate \"#{inspect target}\"
		"""
	def format({:trace, src, :spawn, target, msg}), do: 
		"""
		create \"#{inspect target}\"
		\"#{inspect src}\" -> \"#{inspect target}\": spawn #{inspect msg} 
		activate \"#{inspect target}\"
		"""
	def format({:trace, target, :exit, msg}), do: "destroy \"#{inspect target}\""
	def format({:trace, target, :receive, msg} = m), do: "' ignore receive: #{inspect m}"
	def format(msg), do: "#{inspect msg}"
	

end