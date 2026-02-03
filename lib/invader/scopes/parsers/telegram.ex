defmodule Invader.Scopes.Parsers.Telegram do
  @moduledoc """
  Parses Telegram operations into scope strings.

  Converts operations like `"ask"` into scope strings like `"telegram:ask"`.
  """

  @doc """
  Parses a Telegram operation into a scope string.

  ## Examples

      iex> Telegram.parse_operation("ask")
      {:ok, "telegram:ask"}

      iex> Telegram.parse_operation("notify")
      {:ok, "telegram:notify"}

      iex> Telegram.parse_operation(nil)
      {:error, :no_operation}
  """
  def parse_operation(nil), do: {:error, :no_operation}
  def parse_operation(""), do: {:error, :no_operation}

  def parse_operation(operation) when is_binary(operation) do
    {:ok, "telegram:#{operation}"}
  end

  @doc """
  Returns all known Telegram scope definitions.
  """
  def all_scopes do
    %{
      "telegram:ask" => %{
        description: "Send a blocking prompt and wait for user reply",
        command: "invader telegram ask \"message\"",
        category: :interaction
      },
      "telegram:notify" => %{
        description: "Send a fire-and-forget notification",
        command: "invader telegram notify \"message\"",
        category: :notification
      }
    }
  end

  @doc """
  Returns scope definitions filtered by allowed scopes.
  """
  def filter_scopes(allowed_scopes) do
    all_scopes()
    |> Enum.filter(fn {scope, _info} ->
      Invader.Scopes.Checker.allowed?(%{scopes: allowed_scopes}, scope)
    end)
    |> Map.new()
  end

  @doc """
  Checks if a specific operation is allowed based on scopes.
  """
  def operation_allowed?(scopes, operation) do
    case parse_operation(operation) do
      {:ok, scope} ->
        Invader.Scopes.Checker.allowed?(%{scopes: scopes}, scope)

      {:error, _} ->
        false
    end
  end
end
