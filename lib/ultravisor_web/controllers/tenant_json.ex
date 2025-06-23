# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.TenantJSON do
  alias UltravisorWeb.UserJSON

  def show(%{tenant: tenant}) do
    %{
      data: tenant(tenant)
    }
  end

  def show_terminate(%{result: result}) do
    %{result: result}
  end

  defp tenant(tenant) do
    %{tenant | users: Enum.map(tenant.users, &UserJSON.user/1)}
  end
end
