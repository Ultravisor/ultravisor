# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ClientHandler.StatsTest do
  use Ultravisor.E2ECase, async: false

  @moduletag telemetry: true

  def get_net_stat(kind, tenant_id) do
    assert %{
             [:ultravisor, ^kind, :network, :recv] => [{_, recv}],
             [:ultravisor, ^kind, :network, :send] => [{_, sent}]
           } =
             Ultravisor.Support.Metrics.get_all(
               [
                 [:ultravisor, kind, :network, :recv],
                 [:ultravisor, kind, :network, :send]
               ],
               %{tenant: tenant_id}
             )

    %{recv: recv, sent: sent}
  end

  setup ctx do
    if ctx[:external_id] do
      {:ok, db: "postgres", user: "postgres.#{ctx.external_id}"}
    else
      create_instance([__MODULE__, ctx.line])
    end
  end

  # Connect to the instance
  setup ctx do
    conn =
      start_supervised!(
        {SingleConnection,
         hostname: "localhost",
         port: Application.fetch_env!(:ultravisor, :proxy_port_transaction),
         database: ctx.db,
         username: ctx.user,
         password: "postgres"}
      )

    {:ok, conn: conn}
  end

  describe "client network usage" do
    test "increase on query", %{conn: conn, external_id: external_id} do
      pre = get_net_stat(:client, external_id)

      assert {:ok, _} = SingleConnection.query(conn, "SELECT 1")

      post = get_net_stat(:client, external_id)

      assert post.recv > pre.recv
      assert post.sent > pre.sent
    end

    test "increase on just auth", %{external_id: external_id} do
      stat = get_net_stat(:client, external_id)

      assert stat.recv > 0
      assert stat.sent > 0
    end

    test "do not not increase if other tenant is used", %{external_id: external_id} do
      {:ok, other} = create_instance([__MODULE__, "another"])

      pre = get_net_stat(:client, external_id)

      other_conn =
        start_supervised!(
          {SingleConnection,
           hostname: "localhost",
           port: Application.fetch_env!(:ultravisor, :proxy_port_transaction),
           database: other.db,
           username: other.user,
           password: "postgres"},
          id: :postgrex_another
        )

      assert {:ok, _} = SingleConnection.query(other_conn, "SELECT 1")

      assert pre == get_net_stat(:client, external_id)
    end

    @tag external_id: "metrics_tenant"
    @tag ignore: "No idea what are the rules for proxy connectio metrics"
    test "another instance do not send events here", ctx do
      assert {:ok, _pid, node} = Ultravisor.Support.Cluster.start_node()

      # Start pool on local node
      _this_conn =
        start_supervised!(
          {SingleConnection,
           hostname: "localhost",
           port: Application.fetch_env!(:ultravisor, :proxy_port_transaction),
           database: ctx.db,
           username: ctx.user,
           password: "postgres"},
          id: :postgrex_this
        )

      local_pre = get_net_stat(:client, ctx.external_id)

      # Connect via other node and issue a query
      other_conn =
        start_supervised!(
          {SingleConnection,
           hostname: "localhost",
           port: Application.fetch_env!(:ultravisor, :secondary_proxy_port),
           database: ctx.db,
           username: ctx.user,
           password: "postgres"},
          id: :postgrex_another
        )

      assert {:ok, _} = SingleConnection.query(other_conn, "SELECT 1")

      local_post = get_net_stat(:client, ctx.external_id)

      assert nil ==
               :erpc.call(node, Ultravisor.Support.Metrics, :get_all, [
                 [
                   [:ultravisor, :client, :network, :recv],
                   [:ultravisor, :client, :network, :send]
                 ],
                 %{tenant: ctx.external_id}
               ])

      assert local_pre.recv > local_post.recv
      assert local_pre.sent > local_post.sent
    end
  end

  describe "server network usage" do
    test "increase on query", ctx do
      pre = get_net_stat(:db, ctx.external_id)

      assert {:ok, _} = SingleConnection.query(ctx.conn, "SELECT 1")

      post = get_net_stat(:db, ctx.external_id)

      assert post.recv > pre.recv
      assert post.sent > pre.sent
    end

    test "increase on just auth", ctx do
      stat = get_net_stat(:db, ctx.external_id)

      assert stat.recv > 0
      assert stat.sent > 0
    end

    test "do not not increase if other tenant is used", ctx do
      {:ok, other} = create_instance([__MODULE__, "another"])

      pre = get_net_stat(:db, ctx.external_id)

      other_conn =
        start_supervised!(
          {SingleConnection,
           hostname: "localhost",
           port: Application.fetch_env!(:ultravisor, :proxy_port_transaction),
           database: other.db,
           username: other.user,
           password: "postgres"},
          id: :postgrex_another
        )

      assert {:ok, _} = SingleConnection.query(other_conn, "SELECT 1")

      assert pre == get_net_stat(:db, ctx.external_id)
    end
  end
end
