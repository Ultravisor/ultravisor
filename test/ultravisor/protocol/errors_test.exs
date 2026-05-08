# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.ErrorsTest do
  use ExUnit.Case, async: true

  alias Ultravisor.Protocol.Errors.AddressNotAllowedError
  alias Ultravisor.Protocol.Errors.AuthenticationError
  alias Ultravisor.Protocol.Errors.CheckoutTimeoutError
  alias Ultravisor.Protocol.Errors.DbHandlerError
  alias Ultravisor.Protocol.Errors.ExchangeError
  alias Ultravisor.Protocol.Errors.InvalidFormatError
  alias Ultravisor.Protocol.Errors.MaxClientConnectionsError
  alias Ultravisor.Protocol.Errors.MaxPoolsCountError
  alias Ultravisor.Protocol.Errors.QuerySendError
  alias Ultravisor.Protocol.Errors.SSLRequiredError
  alias Ultravisor.Protocol.Errors.TenantOrUserNotFoundError

  test "AuthenticationError message" do
    assert "Authentication error, reason: :wrong_password" ==
             Exception.message(%AuthenticationError{reason: :wrong_password})
  end

  test "SSLRequiredError message" do
    assert "SSL connection is required" == Exception.message(%SSLRequiredError{})
  end

  test "AddressNotAllowedError message" do
    assert "Address not in tenant `allow_list`: \"127.0.0.1\"" ==
             Exception.message(%AddressNotAllowedError{addr: "127.0.0.1"})
  end

  test "TenantOrUserNotFoundError message" do
    assert "Tenant of user not found" == Exception.message(%TenantOrUserNotFoundError{})
  end

  test "MaxClientConnectionsError message" do
    assert "Max client connections reached" == Exception.message(%MaxClientConnectionsError{})
  end

  test "MaxPoolsCountError message" do
    assert "Max pools count reached" == Exception.message(%MaxPoolsCountError{})
  end

  test "ExchangeError message" do
    assert "bad exchange" == Exception.message(%ExchangeError{reason: "bad exchange"})
  end

  test "DbHandlerError message" do
    assert "`DbHandler exited" == Exception.message(%DbHandlerError{})
  end

  test "CheckoutTimeoutError message" do
    assert "Unable to check out process from the pool due to timeout" ==
             Exception.message(%CheckoutTimeoutError{})
  end

  test "QuerySendError message" do
    assert "Error while sending query" == Exception.message(%QuerySendError{})
  end

  test "InvalidFormatError message" do
    assert "Invalid format for `user` or `db_name`" == Exception.message(%InvalidFormatError{})
  end
end
