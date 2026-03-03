# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.Errors do
  use Ultravisor.Protocol.Error

  deferror AuthenticationError, [:reason] do
    def message(%__MODULE__{reason: reason}) do
      "Authentication error, reason: #{inspect(reason)}"
    end
  end

  deferror SSLRequiredError, message: "SSL connection is required"

  @errdoc """
  Address of the connecting client isn't on the list of allowed CIDRs

  ## Solution

  Check value of `allow_list` in your tenant configuration to check if
  the connecting IP is included in one of the provided IP list.
  """
  deferror AddressNotAllowedError, [:addr] do
    def message(%__MODULE__{addr: addr}) do
      "Address not in tenant `allow_list`: #{inspect(addr)}"
    end
  end

  @errdoc "Given tenant ID is not registered in Ultravisor"
  deferror TenantOrUserNotFoundError, message: "Tenant of user not found"

  @errdoc """
  The connection limit has been reached

  ## Solution

  Check connection limit defined for your tenant.
  """
  deferror MaxClientConnectionsError, message: "Max client connections reached"

  deferror MaxPoolsCountError, message: "Max pools count reached"

  deferror ExchangeError, [:reason, :method] do
    def message(%__MODULE__{reason: reason}) do
      reason
    end
  end

  deferror DbHandlerError, message: "`DbHandler exited"

  deferror CheckoutTimeoutError,
    message: "Unable to check out process from the pool due to timeout"

  deferror QuerySendError, [:error, message: "Error while sending query"]

  deferror InvalidFormatError, [
    :user,
    :db_name,
    message: "Invalid format for `user` or `db_name`"
  ]
end
