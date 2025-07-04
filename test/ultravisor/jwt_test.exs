# SPDX-FileCopyrightText: 2025 Supabase <support@supabase.io>
# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: Apache-2.0
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.JwtTest do
  use ExUnit.Case, async: true

  @subject Ultravisor.Jwt

  @secret "my_secret_key"
  @wrong_secret "my_wrong_secret_key"

  describe "authorize/2" do
    test "returns claims for a valid token" do
      token = create_valid_jwt_token()
      assert {:ok, claims} = @subject.authorize(token, @secret)
      assert claims["role"] == "test"
    end

    test "raises an error for non-binary token" do
      assert_raise FunctionClauseError, fn ->
        @subject.authorize(123, @secret)
      end
    end

    test "returns signature_error for a wrong secret" do
      token = create_valid_jwt_token()
      assert {:error, :signature_error} = @subject.authorize(token, @wrong_secret)
    end
  end

  defp create_valid_jwt_token do
    @subject.Token.gen!(%{"role" => "test"}, @secret)
  end
end
