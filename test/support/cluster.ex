# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Support.Cluster do
  @moduledoc """
  This module provides functionality to help handle distributive mode for testing.
  """

  def start_node(name \\ :peer.random_name()) do
    {:ok, pid, node} =
      ExUnit.Callbacks.start_supervised(%{
        id: {:peer, name},
        start:
          {:peer, :start_link,
           [
             %{
               name: name,
               host: ~c"127.0.0.1",
               longnames: true,
               connection: :standard_io
             }
           ]}
      })

    :peer.call(pid, :logger, :add_primary_filter, [
      :sasl_filter,
      {&:logger_filters.domain/2, {:stop, :sub, [:otp, :sasl]}}
    ])

    :peer.call(pid, :logger, :set_primary_config, [:level, :all])
    true = :peer.call(pid, :code, :set_path, [:code.get_path()])
    apply_config(pid)
    :peer.call(pid, Application, :ensure_all_started, [:ultravisor])

    {:ok, pid, node}
  end

  defp apply_config(pid) do
    for {app_name, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app_name) do
        val =
          case {app_name, key} do
            {:ultravisor, :proxy_port_transaction} ->
              Application.get_env(:ultravisor, :secondary_proxy_port)

            {:ultravisor, UltravisorWeb.Endpoint} ->
              put_in(val[:http],
                ip: {127, 0, 0, 1},
                port: 0
              )

            {:ultravisor, :region} ->
              "usa"

            {:ultravisor, :availability_zone} ->
              "ap-southeast-1c"

            _ ->
              val
          end

        :peer.call(pid, Application, :put_env, [app_name, key, val])
      end
    end
  end
end
