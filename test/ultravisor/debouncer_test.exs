# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.DebouncerTest do
  use ExUnit.Case, async: false

  @subject Ultravisor.Debouncer

  doctest @subject

  describe "debounce/3" do
    test "immediate call after previous one is not fired" do
      ref = make_ref()

      assert {ref, 0} == @subject.debounce(:test, fn -> send(self(), {ref, 0}) end)
      assert {ref, 0} == @subject.debounce(:test, fn -> send(self(), {ref, 1}) end)

      assert_received {^ref, 0}
      refute_received {^ref, 1}
    end

    test "call after timeout refire event" do
      ref = make_ref()

      assert {ref, 0} == @subject.debounce(:test, 10, fn -> send(self(), {ref, 0}) end)
      Process.sleep(20)
      assert {ref, 1} == @subject.debounce(:test, 10, fn -> send(self(), {ref, 1}) end)

      assert_received {^ref, 0}
      assert_received {^ref, 1}
    end
  end
end
