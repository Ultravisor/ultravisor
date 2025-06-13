# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
#
# SPDX-License-Identifier: Apache-2.0

defmodule Supavisor.Vault do
  @moduledoc false
  use Cloak.Vault, otp_app: :supavisor
end
