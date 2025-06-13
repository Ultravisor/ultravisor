# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

[
  import_deps: [:ecto, :phoenix, :open_api_spex],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations", "test"]
]
