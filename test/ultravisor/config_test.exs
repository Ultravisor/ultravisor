# SPDX-FileCopyrightText: 2025 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.ConfigTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @subject Ultravisor.Config

  doctest @subject

  setup ctx do
    env_name = String.replace(to_string(ctx.test), ~r/\W/, "_")

    on_exit(fn ->
      System.delete_env(env_name)
    end)

    {:ok, env_name: env_name}
  end

  describe "get_bool/2" do
    test "default default is `true`", ctx do
      assert @subject.get_bool(ctx.env_name) == true
    end

    property "when the environment variable isn't set returns default", ctx do
      check all default <- boolean() do
        assert @subject.get_bool(ctx.env_name, default) == default
      end
    end

    test "`false` string in environment results in `false`", ctx do
      System.put_env(ctx.env_name, "false")

      assert @subject.get_bool(ctx.env_name) == false
    end

    test "`0` string in environment results in `false`", ctx do
      System.put_env(ctx.env_name, "0")

      assert @subject.get_bool(ctx.env_name) == false
    end

    property "any other value results in `true`", ctx do
      check all val <- string(:printable), val not in ~w[false 0] do
        System.put_env(ctx.env_name, val)

        assert @subject.get_bool(ctx.env_name) == true
      end
    end
  end

  describe "get_integer/2" do
    property "when the environment variable isn't set returns default", ctx do
      check all default <- integer() do
        assert @subject.get_integer(ctx.env_name, default) == default
      end
    end

    property "for given integer representation returns that integer", ctx do
      check all val <- integer() do
        System.put_env(ctx.env_name, to_string(val))

        assert @subject.get_integer(ctx.env_name) == val
      end
    end

    property "non-integer values result in error", ctx do
      check all val <- integer() do
        System.put_env(ctx.env_name, "a#{val}")

        assert_raise ArgumentError, fn -> @subject.get_integer(ctx.env_name) end

        System.put_env(ctx.env_name, "#{val}.0")

        assert_raise ArgumentError, fn -> @subject.get_integer(ctx.env_name) end
      end
    end
  end

  describe "get_enum/3" do
    property "when the environment variable isn't set returns default", ctx do
      values = [:red, :green, :blue]

      check all default <- one_of(values) do
        assert @subject.get_enum(ctx.env_name, values, default) == default
      end
    end

    property "returns value if the value is one of the allowed", ctx do
      check all values <- list_of(atom(:alphanumeric), min_length: 1),
                val <- one_of(values) do
        System.put_env(ctx.env_name, to_string(val))

        assert @subject.get_enum(ctx.env_name, values) == val
      end
    end

    property "raises if the value is not one of the allowed", ctx do
      check all values <- list_of(atom(:alphanumeric), min_length: 1),
                val <- atom(:alphanumeric),
                val not in values do
        System.put_env(ctx.env_name, to_string(val))

        assert_raise RuntimeError, fn -> @subject.get_enum(ctx.env_name, values) end
      end
    end
  end

  describe "get_list/2" do
    property "when the environment variable isn't set returns default", ctx do
      check all default <- list_of(term()) do
        assert @subject.get_list(ctx.env_name, default) == default
      end
    end

    property "returns values split by comma", ctx do
      check all val <- list_of(string(:alphanumeric, min_length: 2)) do
        System.put_env(ctx.env_name, Enum.join(val, ","))

        assert @subject.get_list(ctx.env_name) == val
      end
    end
  end

  describe "get_json/1" do
    property "when the environment variable isn't set returns default", ctx do
      check all default <- map_of(string(:alphanumeric), string(:alphanumeric)) do
        assert @subject.get_json(ctx.env_name, default) == default
      end
    end

    property "returns decoded data", ctx do
      check all default <- map_of(string(:alphanumeric), string(:alphanumeric)) do
        System.put_env(ctx.env_name, JSON.encode!(default))

        assert @subject.get_json(ctx.env_name, default) == default
      end
    end
  end
end
