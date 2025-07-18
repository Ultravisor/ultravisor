# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.MetricsTest do
  use UltravisorWeb.ConnCase, async: true

  alias Ultravisor.Support.Cluster

  @tag cluster: true
  test "exporting metrics", %{conn: conn} do
    {:ok, _pid, node2} = Cluster.start_node()

    Node.connect(node2)

    conn =
      conn
      |> auth
      |> get(~p"/metrics")

    assert conn.status == 200
  end

  test "invalid jwt", %{conn: conn} do
    token = "invalid"

    conn =
      conn
      |> auth(token)
      |> get(~p"/metrics")

    assert conn.status == 403
  end

  defp auth(conn, bearer \\ gen_token()) do
    put_req_header(conn, "authorization", "Bearer " <> bearer)
  end

  defp gen_token(secret \\ Application.fetch_env!(:ultravisor, :metrics_jwt_secret)) do
    Ultravisor.Jwt.Token.gen!(secret)
  end
end
