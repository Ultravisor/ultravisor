# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Queproc.Supervisor do
  use DynamicSupervisor

  def start_link(init) do
    DynamicSupervisor.start_link(__MODULE__, init)
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
