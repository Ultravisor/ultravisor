# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.PreparedStatements.BackendStorage.LRUTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.Protocol.PreparedStatements.BackendStorage.LRU

  test "evicts the least recently used statement" do
    storage =
      @subject.new() |> @subject.put("one") |> @subject.put("two") |> @subject.put("three")

    storage = @subject.touch(storage, "one")

    assert {["two"], storage} = @subject.evict(storage, 1)
    refute @subject.member?(storage, "two")
    assert @subject.member?(storage, "one")
    assert @subject.member?(storage, "three")
  end

  test "put refreshes an existing statement" do
    storage = @subject.new() |> @subject.put("one") |> @subject.put("two") |> @subject.put("one")

    assert {["two"], storage} = @subject.evict(storage, 1)
    assert @subject.size(storage) == 1
  end

  test "delete removes a statement without changing other entries" do
    storage = @subject.new() |> @subject.put("one") |> @subject.put("two")
    storage = @subject.delete(storage, "one")

    refute @subject.member?(storage, "one")
    assert @subject.member?(storage, "two")
  end

  test "evicts several statements from least to most recently used" do
    storage =
      @subject.new()
      |> @subject.put("one")
      |> @subject.put("two")
      |> @subject.put("three")
      |> @subject.touch("one")

    assert {["two", "three"], storage} = @subject.evict(storage, 2)
    assert @subject.member?(storage, "one")
    assert @subject.size(storage) == 1

    assert {["one"], storage} = @subject.evict(storage, 1)
    assert @subject.size(storage) == 0
  end

  test "evict removes entries from the tracked order" do
    storage =
      @subject.new() |> @subject.put("one") |> @subject.put("two") |> @subject.put("three")

    {["one"], storage} = @subject.evict(storage, 1)

    storage = @subject.put(storage, "one")

    assert {["two"], storage} = @subject.evict(storage, 1)
    assert @subject.member?(storage, "one")
    assert @subject.member?(storage, "three")
  end

  test "evict returns every remaining entry when the count exceeds the size" do
    storage = @subject.new() |> @subject.put("one") |> @subject.put("two")

    assert {deleted, storage} = @subject.evict(storage, 5)
    assert Enum.sort(deleted) == ["one", "two"]
    assert @subject.size(storage) == 0
  end

  test "touch and delete ignore an unknown statement" do
    storage = @subject.new() |> @subject.put("one")

    assert @subject.touch(storage, "missing") == storage
    assert @subject.delete(storage, "missing") == storage
    assert @subject.size(storage) == 1
  end
end
