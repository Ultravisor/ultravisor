# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.MixProject do
  use Mix.Project

  def project do
    [
      app: :ultravisor,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      dialyzer: [plt_add_apps: [:mix]],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Ultravisor.Application, []},
      extra_applications:
        [:logger, :runtime_tools, :os_mon, :ssl] ++ extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:dev), do: [:wx, :observer]
  defp extra_applications(_), do: []

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.2"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_view, "~> 2.0.2"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:telemetry_poller, "~> 1.0"},
      {:peep, "~> 3.4"},
      {:plug_cowboy, "~> 2.5"},
      {:joken, "~> 2.6.0"},
      {:cloak_ecto, "~> 1.3.0"},
      {:req, "~> 0.5"},
      {:prom_ex, "~> 1.10"},
      {:open_api_spex, "~> 3.16"},
      {:libcluster, "~> 3.5"},
      {:cachex, "~> 3.6"},
      {:inet_cidr, "~> 1.0.0"},
      {:observer_cli, "~> 1.7"},
      {:sauron, github: "hauleth/sauron"},

      # pooller
      # {:poolboy, "~> 1.5.2"},
      {:poolboy, git: "https://github.com/supabase/poolboy", tag: "v0.0.1"},
      {:syn, "~> 3.3"},
      {:pgo, "~> 0.13"},
      {:rustler, "~> 0.36.1"},
      {:ranch, "~> 2.0", override: true},

      # Linting
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

      # Benchmarking and performance
      {:benchee, "~> 1.3", only: :dev},
      {:eflambe, "~> 0.3.1", only: :dev},

      # Test utilities
      {:excoveralls, ">= 0.0.0", only: [:dev, :test]},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      # Override needed due to eflambe
      {:meck, "~> 1.0", only: [:dev, :test], override: true}
    ]
  end

  def releases do
    [
      ultravisor: [
        steps: [:assemble, :tar],
        include_erts: System.get_env("INCLUDE_ERTS", "true") == "true",
        cookie: System.get_env("RELEASE_COOKIE", Base.url_encode64(:crypto.strong_rand_bytes(30)))
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
      test: [
        "ecto.create",
        "run priv/repo/seeds_before_migration.exs",
        "ecto.migrate --prefix _ultravisor --log-migrator-sql",
        "run priv/repo/seeds_after_migration.exs",
        "test"
      ]
    ]
  end

  defp version, do: File.read!("./VERSION") |> String.trim()
end
