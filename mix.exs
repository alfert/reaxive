defmodule Reaxive.Mixfile do
  use Mix.Project

  def project do
    [ app: :reaxive,
      version: "0.0.2-dev",
      elixir: "~> 1.0.0",
      docs: [readme: true],

      #########
      ## Something on coveralls fails - why???
      ##   what is different to coverex?
      test_coverage: [tool: Coverex.Task, log: :info, coveralls: true],
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: { Reaxive, [] },
      applications: [:kernel , :stdlib, :sasl, :logger, :httpoison]
    ]
  end

  defp deps do
    [      
      {:coverex, "~> 1.0.0", only: :test},
      # {:coverex, "~> 0.0.7-dev", path: "../coverex", only: :test},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.6", only: :dev},
      {:dialyze, "~> 0.1.2", only: :dev},
      {:dbg, github: "fishcakez/dbg", only: :test}
   ]
  end
end
