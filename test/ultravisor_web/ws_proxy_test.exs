# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule UltravisorWeb.WsProxyTest do
  use ExUnit.Case, async: true
  alias UltravisorWeb.WsProxy

  @password_pkt <<?p, 13::32, "postgres", 0>>

  test "filter the password packet" do
    bin = "hello"
    assert WsProxy.filter_pass_pkt(<<@password_pkt::binary, bin::binary>>) == bin
    assert WsProxy.filter_pass_pkt(bin) == bin
  end
end
