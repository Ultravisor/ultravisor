# SPDX-FileCopyrightText: 2026 Łukasz Niemier <~@hauleth.dev>
#
# SPDX-License-Identifier: EUPL-1.2

defmodule Ultravisor.Protocol.Error do
  @moduledoc """
  Macros and functions for properly handling Elixir exceptions as Postgres errors
  """
  alias Ultravisor.Protocol.Server

  def encode(%mod{__exception__: true} = exception, stacktrace \\ []) do
    severity = severity(exception)
    msg = Exception.message(exception)
    code = error_code(exception)

    name =
      case inspect(mod) do
        "Ultravisor.Protocol.Errors." <> name -> name
        other -> other
      end

    Server.encode_error_message(
      [
        ["S", severity],
        ["V", severity],
        ["C", code],
        ["M", [name, ": ", msg]]
      ] ++ encode_location(stacktrace)
    )
  end

  defp encode_location(entries) do
    entry =
      Enum.find(entries, fn {mod, _, _, _} ->
        String.starts_with?(inspect(mod), "Ultravisor")
      end)

    case entry do
      nil ->
        []

      {mod, func, args, location} ->
        [
          ["F", location[:file]],
          ["L", Integer.to_string(location[:line])],
          ["R", format_routine(mod, func, args)]
        ]
    end
  end

  defp format_routine(mod, func, args) when is_number(args),
    do: "#{inspect(mod)}.#{func}/#{args}"

  defp format_routine(mod, func, args) when is_list(args),
    do: "#{inspect(mod)}.#{func}/#{length(args)}"

  defp error_code(%_{pg_code: code}), do: code
  defp error_code(%_{}), do: "UV000"

  defp severity(%_{pg_severity: sev}), do: normalise_severity(sev)
  defp severity(%_{}), do: "FATAL"

  defp normalise_severity(:panic), do: "PANIC"
  defp normalise_severity(:fatal), do: "FATAL"
  defp normalise_severity(:error), do: "ERROR"
  defp normalise_severity(:warning), do: "WARNING"
  defp normalise_severity(:notice), do: "NOTICE"
  defp normalise_severity(:debug), do: "DEBUG"
  defp normalise_severity(:info), do: "INFO"
  defp normalise_severity(:log), do: "LOG"

  defmacro __using__(opts \\ []) do
    quote do
      import unquote(__MODULE__), only: [deferror: 2, deferror: 3]

      @before_compile unquote(__MODULE__)

      @current_pg_code unquote(opts[:start_code] || 1)

      @error_prefix unquote(opts[:prefix] || "UV")
    end
  end

  @doc comptime: true
  defmacro deferror(name, opts, body \\ [do: nil]) do
    quote do
      doc = Module.delete_attribute(__MODULE__, :errdoc) || ""

      code =
        if unquote(opts[:pg_code]) do
          unquote(opts[:pg_code])
        else
          tmp = @current_pg_code
          @current_pg_code tmp + 1
          @error_prefix <> (tmp |> Integer.to_string() |> String.pad_leading(3, "0"))
        end

      defmodule unquote(name) do
        @moduledoc doc

        Module.register_attribute(__MODULE__, :code, persist: true)
        Module.register_attribute(__MODULE__, :desc, persist: true)

        defexception [unquote_splicing(opts), pg_code: code]

        @code code
        @desc doc |> String.split("\n", parts: 2) |> List.first()

        unquote(body[:do])
      end
    end
  end

  @doc comptime: true
  defmacro __before_compile__(env) do
    errors_list =
      for mod <- env.context_modules,
          mod != env.module do
        name = mod |> Module.split() |> List.last()
        attrs = mod.__info__(:attributes)

        {hd(attrs[:code]), name, inspect(mod), hd(attrs[:desc])}
      end
      |> Enum.sort()
      |> Enum.map_join("\n", fn {code, name, mod, desc} ->
        "| [`#{name}`](`#{mod}`) | `#{code}` | #{desc} |"
      end)

    quote do
      @moduledoc """
      Error codes that can be returned to PostgreSQL connections to Ultravisor:

      | Name | Code | Description |
      | ---- | ---- | ---- |
      | Unknown error | `UV000` | Generic error code returned for unknown errors |
      #{unquote(errors_list)}
      """
    end
  end
end
