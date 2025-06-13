# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

import Ecto.Adapters.SQL, only: [query: 3]

[
  "create schema if not exists _ultravisor"
]
|> Enum.each(&query(Ultravisor.Repo, &1, []))
