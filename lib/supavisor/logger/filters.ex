# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Logger.Filters do
  @moduledoc """
  Useful logger filters.
  """

  @doc """
  Log events that are fired by `Ultravisor.ClientHandler` only when the module
  state is equal to `state`.
  """
  @spec filter_client_handler(:logger.log_event(), atom()) :: :logger.filter_return()
  def filter_client_handler(log_event, state) do
    %{meta: meta} = log_event

    case meta do
      %{mfa: {Ultravisor.ClientHandler, _, _}, state: ^state} ->
        log_event

      _ ->
        :ignore
    end
  end
end
