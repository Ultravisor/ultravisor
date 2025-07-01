# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.UserJSON do
  def user(%{} = user) do
    %{
      db_user_alias: user.db_user_alias,
      db_user: user.db_user,
      pool_size: user.pool_size,
      is_manager: user.is_manager,
      mode_type: user.mode_type,
      pool_checkout_timeout: user.pool_checkout_timeout,
      max_clients: user.max_clients
    }
  end
end
