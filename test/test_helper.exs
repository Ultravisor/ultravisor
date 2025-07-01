# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

{:ok, _} = Node.start(:"primary@127.0.0.1", :longnames)

Cachex.start_link(name: Ultravisor.Cache)

logs =
  case System.get_env("TEST_LOGS", "all") do
    level when level in ~w[all true] ->
      true

    level when level in ~w[emergency alert critical error warning notice info debug] ->
      [level: String.to_existing_atom(level)]

    "warn" ->
      [level: :warning]

    level when level in ~w[none disabled false] ->
      false
  end

ExUnit.start(
  formatters: [JUnitFormatter, ExUnit.CLIFormatter],
  capture_log: logs,
  exclude: [
    flaky: true,
    integration: true
  ]
)

Ecto.Adapters.SQL.Sandbox.mode(Ultravisor.Repo, :auto)
