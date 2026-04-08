# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Queproc do
  @moduledoc """
  Message-less queue implementation.

  Most common queue implementation in Erlang is using single process to manage
  the processes in queue. This approach has substantial problem - it needs to
  use messages to coordinate checking out worker processes. That is simple
  approach, but can be noticeable slowdown in high-performance environments.
  This library instead uses Rust NIF with internally mutable queue stored behind
  mutex to be able to handle message-less checkouts.

  This implementation do not guarantee any checkout order from the available
  workers set.

  Additional feature of this implementation is that it allows storing metadata
  attached to the worker. The idea there is that sometimes we need to extract some
  data from the worker process (for example socket connection) and that data is
  immutable on its own. That feature allows to reduce amount of passed messages even
  further.
  """
  use GenServer, type: :supervisor

  alias Queproc.Native, as: Q

  defstruct queue: nil,
            worker_spec: nil,
            meta: nil,
            size: 0,
            max_size: 0,
            idle_timeout: 1_000,
            start_timeout: 5000,
            await_workers: %{},
            workers: MapSet.new()

  def checkout({queue, tid}, timeout) do
    case Q.checkout(queue) do
      {:closed, nil, 0} ->
        {:error, :timeout}

      {:worker, pid, 0} ->
        lookup_worker(tid, pid)

      {:wait, nil, waiter_id} ->
        receive do
          {:worker_available, ^waiter_id, pid} ->
            if Q.accept(queue, waiter_id),
              do: lookup_worker(tid, pid),
              else: {:error, :timeout}

          {:queue_closed, ^waiter_id} ->
            {:error, :timeout}
        after
          timeout ->
            Q.cancel_wait(queue, waiter_id)
            {:error, :timeout}
        end
    end
  end

  defp lookup_worker(tid, pid) do
    case :ets.lookup(tid, pid) do
      [{^pid, term}] -> {:ok, pid, term}
      [] -> {:error, :timeout}
    end
  end

  def checkin({queue, _tid}, pid) do
    Q.checkin(queue, pid)
    :ok
  end

  def get_queue(pid) when is_pid(pid), do: GenServer.call(pid, :get_queue)

  def stats({queue, _}) when is_reference(queue) do
    {owner, available, total, waiters} = Q.stats(queue)
    %{owner: owner, available: available, total: total, queue: waiters}
  end

  def stats(pid) when is_pid(pid), do: stats(get_queue(pid))

  def start_link(opts) do
    {worker_mod, worker_arg} = Access.fetch!(opts, :worker)
    size = Access.fetch!(opts, :size)
    max_size = Access.get(opts, :max_size, size)
    idle_timeout = Access.get(opts, :idle_timeout, 1_000)
    start_timeout = Access.get(opts, :start_timeout, 5_000)

    proc_opts =
      if name = Keyword.get(opts, :name) do
        [name: name]
      else
        []
      end

    unless is_integer(size) and size > 0,
      do: raise(ArgumentError, ":size must be a positive integer")

    unless is_integer(max_size) and max_size >= size,
      do: raise(ArgumentError, ":max_size must be an integer greater than or equal to :size")

    unless is_integer(idle_timeout) and idle_timeout >= 0,
      do: raise(ArgumentError, ":idle_timeout must be a non-negative integer in milliseconds")

    with {:ok, pid} <-
           GenServer.start_link(
             __MODULE__,
             {{worker_mod, worker_arg}, size, max_size, idle_timeout, start_timeout},
             proc_opts
           ) do
      {:ok, pid, get_queue(pid)}
    end
  end

  @impl GenServer
  def init({worker, size, max_size, idle_timeout, start_timeout}) do
    Process.flag(:trap_exit, true)
    Process.set_label("Queproc")

    state = %__MODULE__{
      queue: Q.new(),
      meta: :ets.new(:queproc, [:public, read_concurrency: true, write_concurrency: :auto]),
      worker_spec: worker,
      size: size,
      max_size: max_size,
      idle_timeout: idle_timeout,
      start_timeout: start_timeout
    }

    Process.send_after(self(), :cleanup, 100)

    {:ok, state, {:continue, :start_workers}}
  end

  @impl GenServer
  def handle_continue(:start_workers, state), do: {:noreply, ensure_workers(state), :hibernate}

  @impl true
  def handle_info(:more_power, state), do: {:noreply, ensure_workers(state), :hibernate}

  def handle_info(:cleanup, state) do
    retired = Q.cleanup(state.queue, state.max_size - state.size, state.idle_timeout)

    :ok = Enum.each(retired, &:ets.delete(state.pid, &1))

    Process.send_after(self(), :cleanup, 100)

    {:noreply, state}
  end

  def handle_info({:ack, pid, {:ok, pid, term}}, state) do
    case Map.pop(state.await_workers, pid) do
      {nil, _} ->
        {:noreply, state}

      {{ref, timer}, await_workers} ->
        Process.demonitor(ref, [:flush])
        Process.cancel_timer(timer)
        flush_timer(pid, ref)
        :ets.insert(state.meta, {pid, term})

        if Q.insert(state.queue, pid) do
          state = %{
            state
            | await_workers: await_workers,
              workers: MapSet.put(state.workers, pid)
          }

          {:noreply, state, :hibernate}
        else
          :ets.delete(state.meta, pid)
          stop_worker(pid)
          {:noreply, %{state | await_workers: await_workers}, :hibernate}
        end
    end
  end

  def handle_info({:ack, pid, {:ok, pid}}, state) do
    handle_info({:ack, pid, {:ok, pid, []}}, state)
  end

  def handle_info({:ack, pid, _error}, state), do: fail_startup(pid, state, true)
  def handle_info({:nack, pid, _}, state), do: fail_startup(pid, state, false)

  def handle_info({:timeout, pid, ref}, state) do
    case Map.get(state.await_workers, pid) do
      {^ref, _timer} ->
        state = remove_startup(pid, state)
        Process.unlink(pid)
        Process.exit(pid, :kill)
        flush_exit(pid)
        {:noreply, ensure_workers(state), :hibernate}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.await_workers, pid) do
      {^ref, timer} ->
        Process.cancel_timer(timer)
        flush_timer(pid, ref)

        {:noreply, ensure_workers(%{state | await_workers: Map.delete(state.await_workers, pid)}),
         :hibernate}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, pid, _reason}, state) do
    :ets.delete(state.meta, pid)
    {:noreply, ensure_workers(%{state | workers: MapSet.delete(state.workers, pid)}), :hibernate}
  end

  @impl GenServer
  def handle_call(:get_queue, _ref, state), do: {:reply, {state.queue, state.meta}, state}

  @impl GenServer
  def terminate(_reason, state) do
    Q.close(state.queue)

    Enum.each(state.await_workers, fn {pid, {_ref, timer}} ->
      Process.cancel_timer(timer)
      stop_worker(pid)
    end)

    Enum.each(state.workers, &stop_worker/1)

    :ok
  end

  defp ensure_workers(state) do
    {_owner, _available, registered, waiters} = Q.stats(state.queue)
    pending = map_size(state.await_workers)
    needed_pending = max(max(state.size - registered, 0), waiters)
    slots = max(state.max_size - registered - pending, 0)
    spawn_count = min(max(needed_pending - pending, 0), slots)

    if spawn_count == 0 do
      state
    else
      {mod, args} = state.worker_spec

      new_async =
        Enum.reduce(1..spawn_count, state.await_workers, fn _, await_workers ->
          {pid, ref} = :proc_lib.spawn_opt(mod, :init, [args], [:link, :monitor])
          timer = Process.send_after(self(), {:timeout, pid, ref}, state.start_timeout)
          Map.put(await_workers, pid, {ref, timer})
        end)

      %{state | await_workers: new_async}
    end
  end

  defp fail_startup(pid, state, kill?) do
    case Map.get(state.await_workers, pid) do
      {ref, _timer} ->
        state = remove_startup(pid, state)

        if kill? do
          Process.unlink(pid)
          Process.exit(pid, :kill)
        end

        flush_exit(pid)
        flush_down(pid, ref)
        flush_timer(pid, ref)
        {:noreply, ensure_workers(state), :hibernate}

      _ ->
        {:noreply, state}
    end
  end

  defp remove_startup(pid, state) do
    case Map.pop(state.await_workers, pid) do
      {nil, _} ->
        state

      {{_ref, timer}, await_workers} ->
        Process.cancel_timer(timer)
        %{state | await_workers: await_workers}
    end
  end

  defp stop_worker(pid) do
    :proc_lib.stop(pid, :shutdown, 5_000)
  catch
    _, _ -> Process.exit(pid, :kill)
  end

  defp flush_exit(pid) do
    receive do
      {:EXIT, ^pid, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp flush_down(pid, ref) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp flush_timer(pid, ref) do
    receive do
      {:timeout, ^pid, ^ref} -> :ok
    after
      0 -> :ok
    end
  end
end
