defmodule InvaderWeb.ProxyController do
  @moduledoc """
  API endpoint for CLI proxy requests.
  Sprites use this to execute GitHub commands through Invader.
  """
  use InvaderWeb, :controller

  alias Invader.Connections.Connection
  alias Invader.Connections.GitHub.Executor

  @doc """
  Execute a proxied command.

  ## Request body

      {
        "action": "gh",
        "input": {
          "args": ["pr", "list", "--repo", "owner/repo"],
          "mode": "proxy",  // optional, auto-detected if not specified
          "connection_id": "uuid"  // optional, uses first github connection if not specified
        }
      }

  ## Response

  For proxy mode:

      {"mode": "proxy", "output": "..."}

  For token mode:

      {"mode": "token", "token": "...", "expires_at": "..."}

  On error:

      {"error": "..."}
  """
  def run(conn, %{"action" => "gh", "input" => input}) do
    args = input["args"] || []
    mode = parse_mode(input["mode"])
    connection_id = input["connection_id"]
    sprite_id = input["sprite_id"]

    case get_connection(connection_id) do
      {:ok, connection} ->
        opts = [sprite_id: sprite_id]
        opts = if mode, do: Keyword.put(opts, :mode, mode), else: opts

        case Executor.execute(connection, args, opts) do
          {:ok, result} ->
            json(conn, result)

          {:error, %{exit_code: code, output: output}} ->
            conn
            |> put_status(400)
            |> json(%{error: "Command failed", exit_code: code, output: output})

          {:error, reason} when is_binary(reason) ->
            conn
            |> put_status(400)
            |> json(%{error: reason})

          {:error, reason} ->
            conn
            |> put_status(400)
            |> json(%{error: inspect(reason)})
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "No GitHub connection configured"})
    end
  end

  def run(conn, %{"action" => action}) do
    conn
    |> put_status(400)
    |> json(%{error: "Unknown action: #{action}"})
  end

  def run(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing action parameter"})
  end

  defp parse_mode(nil), do: nil
  defp parse_mode("proxy"), do: :proxy
  defp parse_mode("token"), do: :token
  defp parse_mode(_), do: nil

  defp get_connection(nil) do
    case Connection.get_by_type(:github) do
      {:ok, connection} -> {:ok, connection}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp get_connection(id) do
    case Connection.get(id) do
      {:ok, connection} -> {:ok, connection}
      {:error, _} -> {:error, :not_found}
    end
  end
end
