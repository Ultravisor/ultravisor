# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.FixturesHelpers do
  @moduledoc false

  def start_pool(id, secret) do
    secret = {:password, fn -> secret end}
    Supavisor.start(id, secret)
  end
end
