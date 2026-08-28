# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.PreparedStatements.BackendStorage do
  @moduledoc """
  Tracks prepared statements that exist on one database connection.
  """

  @type name() :: binary()
  @type t() :: struct()

  @callback new() :: t()
  @callback size(t()) :: non_neg_integer()
  @callback member?(t(), name()) :: boolean()
  @callback put(t(), name()) :: t()
  @callback touch(t(), name()) :: t()
  @callback delete(t(), name()) :: t()
  @callback evict(t(), pos_integer()) :: {[name()], t()}
end
