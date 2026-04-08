# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule QueprocTest do
  use ExUnit.Case, async: true

  import Ultravisor.Asserts

  @subject Queproc

  doctest @subject

  defmodule Worker do
    def init(term) do
      case term do
        nil ->
          :proc_lib.init_ack({:ok, self()})

        {:timeout, timeout} ->
          Process.sleep(timeout)
          :proc_lib.init_ack({:ok, self(), :done})

        {:raise, message} ->
          raise message

        {:error, reason} ->
          :proc_lib.init_fail({:error, reason}, {:error, reason})

        {:exit, reason} ->
          exit(reason)

        term ->
          :proc_lib.init_ack({:ok, self(), term})
      end

      :gen_server.enter_loop(__MODULE__, [], term)
    end
  end

  defp start_pool(opts \\ []) do
    opts =
      Keyword.merge(
        [
          worker: {Worker, :worker},
          size: 1,
          idle_timeout: 100
        ],
        opts
      )

    assert {:ok, pid, pool} =
             start_supervised({@subject, opts})

    assert_eventually(fn -> @subject.stats(pool).available >= 1 end)

    %{pid: pid, pool: pool}
  end

  describe "start_link/1" do
    test "starts the configured workers and exposes their queue" do
      %{pid: pid, pool: pool} = start_pool()
      assert {queue, meta} = pool
      assert {queue, meta} == @subject.get_queue(pid)

      assert_eventually(fn ->
        %{owner: ^pid, available: 1, total: 1, queue: 0} = @subject.stats(pool)
      end)
    end

    test "validates its sizing options" do
      base = [worker: {Worker, :worker}, name: nil, size: 1, max_size: 1, idle_timeout: 0]

      assert_raise ArgumentError, ":size must be a positive integer", fn ->
        @subject.start_link(Keyword.put(base, :size, 0))
      end

      assert_raise ArgumentError,
                   ":max_size must be an integer greater than or equal to :size",
                   fn ->
                     @subject.start_link(Keyword.put(base, :max_size, 0))
                   end

      assert_raise ArgumentError,
                   ":idle_timeout must be a non-negative integer in milliseconds",
                   fn ->
                     @subject.start_link(Keyword.put(base, :idle_timeout, -1))
                   end
    end
  end

  describe "checkout/2 and checkin/2" do
    test "checked out metadata is value returned from process" do
      %{pool: pool} = start_pool(worker: {Worker, 2137})
      assert {:ok, _worker, 2137} = @subject.checkout(pool, 100)
    end

    test "checked out metadata will be `[]` if process do not return any metadata" do
      %{pool: pool} = start_pool(worker: {Worker, nil})
      assert {:ok, _worker, []} = @subject.checkout(pool, 100)
    end

    test "checks out a worker and makes it available after checkin" do
      %{pool: pool} = start_pool()
      assert {:ok, worker, :worker} = @subject.checkout(pool, 100)
      assert %{available: 0, total: 1} = @subject.stats(pool)
      assert :ok == @subject.checkin(pool, worker)
      assert_eventually(fn -> @subject.stats(pool).available == 1 end)
    end

    test "times out when every worker is checked out" do
      %{pool: pool} = start_pool()
      assert {:ok, _worker, :worker} = @subject.checkout(pool, 100)
      assert {:error, :timeout} == @subject.checkout(pool, 10)
    end

    test "if the checking out process dies without checkin, then the process will be made available" do
      %{pool: pool} = start_pool()

      spawn(fn ->
        assert {:ok, _worker, :worker} = @subject.checkout(pool, 100)
      end)

      assert_eventually(fn -> @subject.stats(pool).available == 1 end)
    end
  end

  describe "stats/1" do
    test "the same value is returned when called via PID and when called directly" do
      %{pid: pid, pool: pool} = start_pool(max_size: 2)
      assert @subject.stats(pid) == @subject.stats(pool)
    end
  end

  test "when worker dies, then another one will be spawned" do
    %{pool: pool} = start_pool()
    assert {:ok, worker, :worker} = @subject.checkout(pool, 100)
    assert :ok == @subject.checkin(pool, worker)

    Process.exit(worker, :normal)

    assert @subject.stats(pool).available == 1
    assert_eventually(fn -> @subject.stats(pool).available == 1 end)
  end

  test "idle workers are killed after timeout" do
    %{pool: pool} = start_pool(max_size: 2)

    assert {:ok, worker1, :worker} = @subject.checkout(pool, 100)
    assert {:ok, worker2, :worker} = @subject.checkout(pool, 100)
    assert {:error, :timeout} == @subject.checkout(pool, 10)
    assert :ok == @subject.checkin(pool, worker1)
    assert :ok == @subject.checkin(pool, worker2)

    assert @subject.stats(pool).available == 2
    assert_eventually(fn -> @subject.stats(pool).available == 1 end)
  end
end
