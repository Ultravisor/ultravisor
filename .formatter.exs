# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

[
  import_deps: [:ecto, :phoenix, :open_api_spex],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations", "test"]
]
