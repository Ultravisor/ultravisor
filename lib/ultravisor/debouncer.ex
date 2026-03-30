# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Debouncer do
  def debounce(key, time \\ 100, func) do
    current = System.monotonic_time(:millisecond)
    key = {:debounce, key}

    case Process.get(key, nil) do
      {prev, ret} when prev + time > current ->
        ret

      _ ->
        ret = func.()
        Process.put(key, {current, ret})
        ret
    end
  end
end
