# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.SynHandlerTest do
  use ExUnit.Case, async: false

  require Logger

  import Ultravisor, only: [conn_id: 1]

  alias Ecto.Adapters.SQL.Sandbox
  alias Ultravisor.Support.Cluster

  @id conn_id(tenant: "syn_tenant", user: "postgres", mode: :session, db_name: "postgres")

  @tag cluster: true
  test "resolving conflict" do
    {:ok, _pid, node2} = Cluster.start_node()

    secret = %{alias: "postgres"}
    auth_secret = {:password, fn -> secret end}
    {:ok, pid2} = :erpc.call(node2, Ultravisor.FixturesHelpers, :start_pool, [@id, secret])
    Process.sleep(500)
    assert pid2 == Ultravisor.get_global_sup(@id)
    assert node(pid2) == node2
    true = Node.disconnect(node2)
    Process.sleep(1000)

    assert nil == Ultravisor.get_global_sup(@id)
    {:ok, pid1} = Ultravisor.start(@id, auth_secret)
    assert pid1 == Ultravisor.get_global_sup(@id)
    assert node(pid1) == node()

    :pong = Node.ping(node2)
    Process.sleep(500)

    assert pid2 == Ultravisor.get_global_sup(@id)
    assert node(pid2) == node2
  end

  setup tags do
    pid = Sandbox.start_owner!(Ultravisor.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
