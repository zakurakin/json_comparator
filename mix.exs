defmodule JsonComparator.MixProject do
  use Mix.Project

  def project do
    [
      app: :json_comparator,
      version: "1.0.1",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test],
      deps: deps(),
      description: "A module for deep json comparison.",
      package: package(),
      source_url: "https://github.com/zakurakin/json_comparator"
    ]
  end

  defp deps do
    [
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:credo, "~> 1.7", runtime: false},
      {:ex_doc, "~> 0.32", runtime: false},
      {:credo_ext, "~> 0.1.1"}
    ]
  end

  defp package do
    [
      name: "json_comparator",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/zakurakin/json_comparator"}
    ]
  end
end
