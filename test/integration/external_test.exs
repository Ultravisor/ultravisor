# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Integration.ExternalTest do
  use Ultravisor.E2ECase,
    async: false,
    parameterize:
      for(
        runtime <- ~w[node bun],
        mode <- ~w[transaction session],
        do: %{runtime: runtime, mode: mode}
      )

  @moduletag integration: true

  setup_all do
    npm =
      get_tool("pnpm") || get_tool("npm") || get_tool("bun") ||
        raise "Cannot find neither Yarn nor NPM"

    Enum.each(~w[js], fn name ->
      assert {_, 0} = System.cmd(npm, ~w[install], cd: suite(name))
    end)

    {:ok, npm: npm}
  end

  setup ctx do
    create_instance([ctx.runtime, ctx.library, ctx.mode])
  end

  setup ctx do
    if get_tool(ctx.runtime) do
      :ok
    else
      raise "Runtime not available"
    end
  end

  @tag library: "postgres.js", suite: "js"
  test "Postgres.js", ctx do
    assert_run(ctx, suite_args(ctx.runtime, "postgres/index.test.js"))
  end

  @tag library: "pg", suite: "js"
  test "pg", ctx do
    assert_run(ctx, suite_args(ctx.runtime, "pg/index.test.js"))
  end

  # Both suites use the built-in Node test runner. Bun runs `node:test` files
  # through its test command, and that command only picks up files with a
  # `.test.js` name. `--test-timeout` matches the 5 second per-test default of
  # the postgres.js suite, which reads it from the TIMEOUT environment
  # variable.
  defp suite_args("node", entry),
    do: ~w[--test --test-timeout=5000 --trace-deprecation] ++ [entry]

  defp suite_args("bun", entry),
    do: ~w[test --timeout=5000 --trace-deprecation] ++ [entry]

  defp assert_run(ctx, args, opts \\ []) do
    suite = suite(ctx.suite)

    env =
      [
        {"PGMODE", ctx.mode},
        {"PGDATABASE", ctx.db},
        {"PGHOST", "localhost"},
        {"PGPORT", to_string(port(ctx.mode))},
        {"PGUSER", ctx.user},
        {"PGPASS", "postgres"}
      ] ++ (opts[:env] || [])

    assert {output, code} =
             System.cmd(ctx.runtime, args,
               env: env,
               cd: suite,
               stderr_to_stdout: true
             )

    assert code == 0, output
  end

  ## UTILS

  defp suite(name), do: Path.join(__DIR__, name)

  defp get_tool(name), do: System.find_executable(name)

  defp port("session"), do: Application.fetch_env!(:ultravisor, :proxy_port_session)
  defp port("transaction"), do: Application.fetch_env!(:ultravisor, :proxy_port_transaction)
end
