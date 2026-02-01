defmodule Invader.Connections.Sprites.TokenProvider do
  @moduledoc """
  Provides Sprites API tokens from stored connections.
  """

  alias Invader.Connections.Connection

  @doc """
  Gets the Sprites API token from the stored connection.
  Returns `{:ok, token}` if found, or `{:error, :not_configured}` if no Sprites connection exists.
  """
  @spec get_token() :: {:ok, String.t()} | {:error, :not_configured}
  def get_token do
    case Connection.get_by_type(:sprites) do
      {:ok, %{token: token}} when is_binary(token) and token != "" ->
        {:ok, token}

      _ ->
        {:error, :not_configured}
    end
  end

  @doc """
  Tests a Sprites connection by attempting to list sprites.
  Returns `{:ok, :connected}` on success, or `{:error, reason}` on failure.
  """
  @spec test_connection(Connection.t()) :: {:ok, :connected} | {:error, term()}
  def test_connection(%{token: token}) when is_binary(token) and token != "" do
    client = Sprites.new(token)

    case Sprites.list(client) do
      {:ok, _sprites} ->
        {:ok, :connected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def test_connection(_connection) do
    {:error, :missing_token}
  end
end
