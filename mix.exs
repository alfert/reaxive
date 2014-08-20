defmodule Reaxive.Mixfile do
  use Mix.Project

  def project do
    [ app: :reaxive,
      version: "0.0.1-dev",
      elixir: "~> 0.15",
      docs: [readme: true],
      test_coverage: [tool: Coverex.Task, log: :info],
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: { Reaxive, [] },
      applications: [:kernel , :stdlib, :sasl]
    ]
  end

  defp deps do
    [      
      {:coverex, "~> 0.0.7", only: :test},
      # {:coverex, "~> 0.0.7-dev", path: "../coverex", only: :test},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.5", only: :dev},
      {:dialyze, "~> 0.1.2", only: :dev}
   ]
  end
end
