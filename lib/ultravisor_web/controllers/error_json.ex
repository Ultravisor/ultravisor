# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See `config/config.exs`.
  """

  def render(template, _assigns) do
    %{
      error: Phoenix.Controller.status_message_from_template(template)
    }
  end
end
