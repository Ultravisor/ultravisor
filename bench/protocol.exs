# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

alias Ultravisor.Protocol.Client

bin_select_1 = <<81, 0, 0, 0, 14, 115, 101, 108, 101, 99, 116, 32, 49, 59, 0>>

Benchee.run(%{
  "Client.decode_pkt/1" => fn ->
    Client.decode_pkt(bin_select_1)
  end
})
