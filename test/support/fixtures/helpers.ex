# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.FixturesHelpers do
  @moduledoc false

  def start_pool(id, secret) do
    secret = {:password, fn -> secret end}
    Ultravisor.start(id, secret)
  end
end
