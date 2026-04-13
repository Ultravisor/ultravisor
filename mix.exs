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
      compilers:
        [
          # :unused
        ] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      docs: docs(),
      unused: unused(),
      dialyzer: [plt_add_apps: [:mix], flags: [:no_opaque]],
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
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

  defp unused do
    [
      ignore: [
        ~r/^UltravisorWeb\..*Controller$/,
        ~r/^UltravisorWeb\.OpenApiSchemas/,
        UltravisorWeb,
        Ultravisor.Config,
        {:_, :child_spec, 1},
        {:_, :start_link, 1},
        {:_, :__using__, 1},
        fn _, meta -> meta.doc_meta[:comptime] end
      ]
    ]
  end

  defp extra_applications(:dev), do: [:wx, :observer]
  defp extra_applications(_), do: []

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      assets: %{
        "guides/images/" => "images"
      },
      extra_section: "GUIDES",
      extras: ["README.md"] ++ Path.wildcard("guides/**/*.md"),
      groups_for_extras: [
        Configuration: ~r"/configuration/",
        Deployment: ~r"/deployment/",
        Connecting: ~r"/connecting/",
        ORMs: ~r"/orms/",
        Monitoring: ~r"/monitoring/",
        Migrating: ~r"/migrating/",
        Development: ~r"/development/"
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.7"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetry, github: "beam-telemetry/telemetry", override: true},
      {:telemetry_metrics, github: "beam-telemetry/telemetry_metrics", override: true},
      {:peep, github: "rkallos/peep", override: true},
      {:plug_cowboy, "~> 2.5"},
      {:joken, "~> 2.6.0"},
      {:cloak_ecto, "~> 1.3.0"},
      {:prom_ex, "~> 1.10"},
      {:open_api_spex, "~> 3.16"},
      {:libcluster, "~> 3.5"},
      {:libcluster_postgres, "~> 0.2.0"},
      {:cachex, "~> 4.0"},
      {:inet_cidr, "~> 1.0.0"},
      {:observer_cli, "~> 1.7"},
      {:sauron, github: "hauleth/sauron"},
      {:mix_unused, github: "hauleth/mix_unused", runtime: false},

      # Documentation
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},

      # pooller
      # {:poolboy, "~> 1.5.2"},
      {:poolboy, github: "hauleth/poolboy"},
      {:syn, "~> 3.3"},
      {:pgo, "~> 0.13"},
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
      {:req, "~> 0.5", only: [:test]},
      {:junit_formatter, "~> 3.4", only: [:test]},
      {:repatch, "~> 1.5", only: [:test]}
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
      ],
      make_help: &make_help/1,
      dev: &run_dev/1
    ]
  end

  defp version, do: File.read!("./VERSION") |> String.trim()

  ## Custom tasks

  defp run_dev(args) do
    {flags, []} =
      OptionParser.parse!(
        args,
        strict: [
          node: :integer
        ]
      )

    node = flags[:node] || 0

    if node < 0 do
      Mix.raise("Invalid node ID")
    end

    # XXX: Better algorithm for finding sensible port values
    port_management = 4000 + node
    port_transaction = 6543 + 10 * node
    port_session = 5432 + 10 * node
    port_proxy = 5412 + 10 * node

    System.put_env([
      {"VAULT_ENC_KEY", "aHD8DZRdk2emnkdktFZRh3E9RNg4aOY7"},
      {"API_JWT_SECRET", "dev"},
      {"METRICS_JWT_SECRET", "dev"},
      {"SECRET_KEY_BASE", "dev"},
      {"ULTRAVISOR_CLUSTER_POSTGRES", "ultravisor_local"},
      {"DB_POOL_SIZE", "5"},
      {"AVAILABILITY_ZONE", "test-#{node}"},
      {"PROXY_PORT_TRANSACTION", to_string(port_transaction)},
      {"PROXY_PORT_SESSION", to_string(port_session)},
      {"PROXY_PORT", to_string(port_proxy)},
      {"ULTRAVISOR_MANAGEMENT_PORT", to_string(port_management)}
    ])

    Node.start(:"ultravisor#{node}@127.0.0.1")
    Node.set_cookie(:cookie)

    Mix.Task.run("run", ["--no-halt"])
  end

  defp make_help([makefile | _]) do
    data = File.read!(makefile)

    tasks =
      Regex.scan(~r/^(?<help>(#[^\n]*\n)*)(?<task>[a-z0-9._-]+):/mi, data, capture: :all_names)

    Mix.shell().info([
      "Usage:\n\n",
      "  ",
      :yellow,
      "make ",
      :green,
      "<task> ",
      :reset,
      "[argument=value]...",
      "\n\n",
      "Tasks:\n"
    ])

    max_task = tasks |> Enum.map(fn [_, name] -> String.length(name) end) |> Enum.max()
    width = max_task + 6

    for [help, name] <- tasks, not String.starts_with?(name, ".") do
      name_width = String.length(name)

      help =
        case String.split(help, "\n", trim: true) do
          [first | rest] ->
            first_pad = List.duplicate(?\s, width - name_width - 2)
            rest_pad = List.duplicate(?\s, width)
            remaining_help = Enum.map(rest, &[rest_pad, &1, "\n"])

            [first_pad, first, "\n" | remaining_help]

          [] ->
            ""
        end

      Mix.shell().info(["  ", :green, name, :reset, help])
    end
  end
end
