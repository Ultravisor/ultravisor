# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Repo do
  use Ecto.Repo,
    otp_app: :supavisor,
    adapter: Ecto.Adapters.Postgres
end
