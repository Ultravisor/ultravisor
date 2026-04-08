# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Queproc.Native do
  use Rustler,
    otp_app: :ultravisor,
    crate: :queproc

  def new, do: :erlang.nif_error(:nif_not_loaded)

  def insert(_queue, _pid), do: :erlang.nif_error(:nif_not_loaded)

  def checkout(_queue), do: :erlang.nif_error(:nif_not_loaded)
  def checkin(_queue, _pid), do: :erlang.nif_error(:nif_not_loaded)

  def cancel_wait(_queue), do: :erlang.nif_error(:nif_not_loaded)

  def drop(_queue, _pid), do: :erlang.nif_error(:nif_not_loaded)

  def to_list(_queue), do: :erlang.nif_error(:nif_not_loaded)

  def size(_queue), do: :erlang.nif_error(:nif_not_loaded)

  def stats(_queue), do: :erlang.nif_error(:nif_not_loaded)
end
