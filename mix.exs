defmodule Reaxive.Mixfile do
  use Mix.Project

  def project do
    [ app: :reaxive,
      version: "0.0.1-dev",
      elixir: "~> 0.15",
      docs: [readme: true],
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
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.5", only: :dev}
   ]
  end
end
