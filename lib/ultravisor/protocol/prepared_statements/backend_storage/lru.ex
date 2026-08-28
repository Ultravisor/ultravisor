# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.PreparedStatements.BackendStorage.LRU do
  @moduledoc """
  Least-recently-used storage for one database connection.

  `sequence` maps a statement name to the counter value of its last use.
  `order` keeps the same `{counter, name}` pairs in an ordered set, so the
  least recently used entry is the smallest pair. Both structures are updated
  together, so eviction takes the smallest entry directly instead of sorting
  every tracked statement.
  """

  @behaviour Ultravisor.Protocol.PreparedStatements.BackendStorage

  @type t() ::
          %__MODULE__{
            counter: non_neg_integer(),
            sequence: %{binary() => pos_integer()},
            order: :gb_sets.set()
          }

  defstruct counter: 0, sequence: %{}, order: :gb_sets.empty()

  @impl true
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @impl true
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{sequence: sequence}), do: map_size(sequence)

  @impl true
  @spec member?(t(), binary()) :: boolean()
  def member?(%__MODULE__{sequence: sequence}, name), do: Map.has_key?(sequence, name)

  @impl true
  @spec put(t(), binary()) :: t()
  def put(%__MODULE__{counter: counter, sequence: sequence, order: order}, name) do
    order =
      case Map.fetch(sequence, name) do
        {:ok, previous} -> :gb_sets.delete({previous, name}, order)
        :error -> order
      end

    counter = counter + 1

    %__MODULE__{
      counter: counter,
      sequence: Map.put(sequence, name, counter),
      order: :gb_sets.add({counter, name}, order)
    }
  end

  @impl true
  @spec touch(t(), binary()) :: t()
  def touch(storage, name) do
    if member?(storage, name), do: put(storage, name), else: storage
  end

  @impl true
  @spec delete(t(), binary()) :: t()
  def delete(%__MODULE__{sequence: sequence, order: order} = storage, name) do
    case Map.fetch(sequence, name) do
      {:ok, counter} ->
        %__MODULE__{
          storage
          | sequence: Map.delete(sequence, name),
            order: :gb_sets.delete({counter, name}, order)
        }

      :error ->
        storage
    end
  end

  @impl true
  @spec evict(t(), pos_integer()) :: {[binary()], t()}
  def evict(%__MODULE__{sequence: sequence} = storage, count) when count > 0 do
    {names, order} = take_smallest(storage.order, count, [])

    {names, %__MODULE__{storage | sequence: Map.drop(sequence, names), order: order}}
  end

  defp take_smallest(order, 0, names), do: {Enum.reverse(names), order}

  defp take_smallest(order, count, names) when count > 0 do
    if :gb_sets.is_empty(order) do
      {names, order}
    else
      {{_counter, name}, order} = :gb_sets.take_smallest(order)
      take_smallest(order, count - 1, [name | names])
    end
  end
end
