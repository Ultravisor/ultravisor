# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Queproc do
  use GenServer, type: :supervisor

  require Logger

  alias Queproc.Native, as: Q

  defstruct queue: nil,
            worker_spec: nil,
            meta: nil,
            size: 0,
            await_workers: %{},
            workers: []

  def checkout({queue, tid}, timeout) do
    case Q.checkout(queue) do
      pid when is_pid(pid) ->
        [{^pid, term}] = :ets.lookup(tid, pid)

        {:ok, pid, term}

      nil ->
        receive do
          {:worker_available, pid} ->
            [{^pid, term}] = :ets.lookup(tid, pid)

            {:ok, pid, term}
        after
          timeout ->
            Q.cancel_wait(queue)
            {:error, :timeout}
        end
    end
  end

  def checkin({queue, tid}, pid) do
    Q.checkin(queue, pid)

    :ok
  end

  def get_queue(pid) when is_pid(pid) do
    GenServer.call(pid, :get_queue)
  end

  def stats({queue, _}) when is_reference(queue) do
    {owner, workers_count, monitors_count, waiters_count} = Q.stats(queue)

    %{
      owner: owner,
      available: workers_count,
      total: monitors_count,
      queue: waiters_count
    }
  end

  def stats(pid) when is_pid(pid) do
    stats(get_queue(pid))
  end

  def start_link(opts) do
    {worker_mod, worker_arg} = Access.fetch!(opts, :worker)
    size = Access.fetch!(opts, :size)
    name = Access.fetch!(opts, :name)

    with {:ok, pid} <-
           GenServer.start_link(__MODULE__, {{worker_mod, worker_arg}, size}, name: name) do
      {:ok, pid, get_queue(pid)}
    end
  end

  @impl GenServer
  def init({worker, size}) do
    Process.flag(:trap_exit, true)

    Process.set_label("Queproc")

    state = %__MODULE__{
      queue: Q.new(),
      meta:
        :ets.new(:queproc, [
          :public,
          read_concurrency: true,
          write_concurrency: :auto
        ]),
      worker_spec: worker,
      size: size
    }

    {:ok, state, {:continue, :start_workers}}
  end

  @impl GenServer
  def handle_continue(:start_workers, %__MODULE__{} = state) do
    {mod, args} = state.worker_spec
    current = Q.size(state.queue)
    waiting = Map.size(state.await_workers)

    Logger.debug(current: current, waiting: waiting)

    new_async =
      for _ <- (current + waiting)..(state.size - 1)//1, into: state.await_workers do
        {pid, ref} =
          :proc_lib.spawn_opt(mod, :init, [args], [:link, :monitor])

        timer = Process.send_after(self(), {:timeout, pid, ref}, 5000)

        {pid, {ref, timer}}
      end

    {:noreply, %{state | await_workers: new_async}, :hibernate}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    Logger.error(%{msg: :worker_died, pid: pid, reason: reason})

    {:noreply, state, {:continue, :start_workers}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %__MODULE__{} = state) do
    rest = Map.delete(state.await_workers, pid)

    Logger.error(%{msg: :worker_startup_failed, pid: pid, reason: reason})

    {:noreply, %{state | await_workers: rest}}
  end

  def handle_info(:more_power, state) do
    # TODO: Overload handling
    {:noreply, state}
  end

  def handle_info({:ack, pid, {:ok, term}}, %__MODULE__{} = state) do
    {{ref, timer}, rest} = Map.pop(state.await_workers, pid)

    Logger.debug(%{msg: :new_worker, pid: pid})

    Process.demonitor(ref, [:flush])
    Process.cancel_timer(timer)

    flush_timer(pid, ref)

    :ets.insert(state.meta, {pid, term})
    Q.insert(state.queue, pid)

    {:noreply, %{state | await_workers: rest}, :hibernate}
  end

  def handle_info({:ack, pid, _error}, %__MODULE__{} = state) do
    {{ref, timer}, rest} = Map.pop(state.await_workers, pid)
    Process.unlink(pid)
    Process.exit(pid, :kill)
    Process.cancel_timer(timer)

    flush_exit(pid)
    flush_down(pid, ref)
    flush_timer(pid, ref)

    {:noreply, %{state | await_workers: rest}, :hibernate}
  end

  def handle_info({:nack, pid, _}, %__MODULE__{} = state) do
    {{ref, timer}, rest} = Map.pop(state.await_workers, pid)
    Process.cancel_timer(timer)

    flush_exit(pid)
    flush_down(pid, ref)
    flush_timer(pid, ref)

    {:noreply, %{state | await_workers: rest}, :hibernate}
  end

  def handle_info({:timeout, pid, ref}, %__MODULE__{} = state) do
    rest = Map.delete(state.await_workers, pid)
    Process.unlink(pid)
    Process.exit(pid, :kill)

    flush_exit(pid)
    flush_down(pid, ref)

    {:noreply, %{state | await_workers: rest}, :hibernate}
  end

  @impl GenServer
  def handle_call(:get_queue, _ref, %__MODULE__{} = state) do
    {:reply, {state.queue, state.meta}, state}
  end

  @impl GenServer
  def terminate(reason, %__MODULE__{} = state) do
    Logger.notice(%{msg: :terminate, reason: reason})

    for pid <- state.workers do
      ref = Process.monitor(pid)
      Process.exit(pid, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          end
      end
    end

    %{state | workers: []}
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
      {:timer, ^pid, ^ref} -> :ok
    after
      0 -> :ok
    end
  end
end
