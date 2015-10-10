defmodule Reaxive.Mixfile do
  use Mix.Project

  def project do
    [ app: :reaxive,
      version: "0.1.1-dev",
      elixir: "~> 1.0",
      package: package,
      name: "Reaxive - a Reactive Extension inspired library for Elixir",
      description: description,
      source_url: "https://github.com/alfert/reaxive",
      homepage_url: "https://github.com/alfert/reaxive",
      docs: [readme: "README.md"],
      test_coverage: [tool: Coverex.Task, log: :info, coveralls: true],
      deps: deps ]
  end

  # Configuration for the OTP applicatioon
  def application do
    [
      mod: { Reaxive, [] },
      applications: [
        # httpoison is used for coverage testing only ...
        # :httpoison,
        # regular dependencies
        :kernel , :stdlib, :sasl, :logger]
    ]
  end

  defp deps do
    [
      {:coverex, "~> 1.4.0", only: :test},
      {:earmark, "~> 0.1.17", only: :dev},
      {:ex_doc, "~> 0.8.4", only: :dev},
      {:dialyze, "~> 0.2.0", only: :dev},
      {:dbg, "~>1.0.0", only: :test},
      {:inch_ex, "~> 0.4.0", only: :docs}
   ]
  end

  # Hex Package description
  defp description do
    """
    Reaxive is a library inspired by Reactive Extensions and ELM to provide
    functional reactive programming to Elixir. It allows for active sequences
    of events and a set of stream-reducer like transformations such as map or
    filter. 
    """
  end

  # Hex Package definition
  defp package do
    [contributors: ["Klaus Alfert"],
     licenses: ["Apache 2.0"],
     links: %{"GitHub" => "https://github.com/alfert/reaxive"}
    ]
  end

end
