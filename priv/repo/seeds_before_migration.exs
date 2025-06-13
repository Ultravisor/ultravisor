# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

import Ecto.Adapters.SQL, only: [query: 3]

[
  "create schema if not exists _supavisor"
]
|> Enum.each(&query(Supavisor.Repo, &1, []))
