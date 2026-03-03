# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ClientHandler.ExchangeTest do
  use ExUnit.Case, async: true

  alias Ultravisor.Helpers

  @subject Ultravisor.ClientHandler.Exchange

  describe "authenticate_exchange/4 :password" do
    test "accepts equal values" do
      assert {:ok, nil} =
               @subject.authenticate_exchange(:password, nil, %{client: "secret"}, "secret")
    end

    test "rejects unequal equal-length values" do
      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(:password, nil, %{client: "secret"}, "secrer")
    end

    test "rejects unequal-length values" do
      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(:password, nil, %{client: "secret"}, "shorter")

      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(
                 :password,
                 nil,
                 %{client: "secret"},
                 "much longer secret"
               )
    end
  end

  describe "authenticate_exchange/4 :auth_query (SCRAM)" do
    setup do
      client_key = :crypto.strong_rand_bytes(32)
      stored_key = Helpers.hash(client_key)

      secrets = fn -> %{stored_key: stored_key} end

      # p decodes to client_key XOR signatures.client
      decoded_p = :crypto.strong_rand_bytes(32)

      signature = %{
        client: :crypto.exor(decoded_p, client_key),
        server: "server-signature"
      }

      p = Base.encode64(decoded_p)

      %{secrets: secrets, signatures: signature, p: p, client_key: client_key}
    end

    test "accepts a valid proof", ctx do
      assert {:ok, _client_key} =
               @subject.authenticate_exchange(:auth_query, ctx.secrets, ctx.signatures, ctx.p)
    end

    test "rejects a wrong proof", ctx do
      bad_p = Base.encode64(:crypto.strong_rand_bytes(32))

      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(:auth_query, ctx.secrets, ctx.signatures, bad_p)
    end

    test "rejects a wrong stored key", ctx do
      wrong_secrets = fn -> %{stored_key: Helpers.hash("other")} end

      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(:auth_query, wrong_secrets, ctx.signatures, ctx.p)
    end
  end

  describe "authenticate_exchange/4 :auth_query_md5" do
    setup do
      server_hash = "md5" <> Helpers.md5("password")
      salt = :crypto.strong_rand_bytes(4)

      valid = "md5" <> Helpers.md5([server_hash, salt])

      %{server_hash: server_hash, salt: salt, valid: valid}
    end

    test "accepts a matching hash", ctx do
      assert {:ok, nil} =
               @subject.authenticate_exchange(
                 :auth_query_md5,
                 ctx.valid,
                 ctx.server_hash,
                 ctx.salt
               )
    end

    test "rejects an unequal equal-length hash", ctx do
      wrong = "md5" <> Helpers.md5([ctx.server_hash, ctx.salt, "foo"])

      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(
                 :auth_query_md5,
                 wrong,
                 ctx.server_hash,
                 ctx.salt
               )
    end

    test "rejects an unequal-length value", ctx do
      assert {:error, "Wrong password"} =
               @subject.authenticate_exchange(
                 :auth_query_md5,
                 "too-short",
                 ctx.server_hash,
                 ctx.salt
               )
    end
  end
end
