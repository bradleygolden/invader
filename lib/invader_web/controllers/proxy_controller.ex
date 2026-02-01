defmodule InvaderWeb.ProxyController do
  @moduledoc """
  API endpoint for CLI proxy requests.
  Sprites use this to execute GitHub commands through Invader.
  """
  use InvaderWeb, :controller

  alias Invader.Connections.Connection
  alias Invader.Connections.GitHub.Executor
  alias Invader.Missions.Mission
  alias Invader.Scopes.Checker
  alias Invader.Scopes.Parsers.GitHub, as: GitHubParser

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
    case verify_sprite_token(conn) do
      {:ok, claims} ->
        args = input["args"] || []
        mode = parse_mode(input["mode"])
        connection_id = input["connection_id"]
        sprite_id = input["sprite_id"]

        # Check scope permissions if mission_id is present in token
        case check_scope_permission(claims, args) do
          :ok ->
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

          {:error, :forbidden, scope} ->
            conn
            |> put_status(403)
            |> json(%{
              error: "Permission denied",
              message: "This mission does not have permission for scope: #{scope}",
              scope: scope
            })
        end

      {:error, :invalid_token} ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid or expired token"})
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

  defp verify_sprite_token(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <-
           Phoenix.Token.verify(InvaderWeb.Endpoint, "sprite_proxy", token, max_age: 86400) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp check_scope_permission(claims, args) do
    mission_id = claims[:mission_id]

    # If no mission_id in token, allow (backward compatibility)
    if is_nil(mission_id) do
      :ok
    else
      case Mission.get(mission_id) do
        {:ok, mission} ->
          # Load scope_preset if needed
          mission = Ash.load!(mission, :scope_preset)

          # Parse args into scope string
          case GitHubParser.parse_args(args) do
            {:ok, scope} ->
              if Checker.allowed?(mission, scope) do
                :ok
              else
                {:error, :forbidden, scope}
              end

            {:error, :no_command} ->
              # No command specified, allow (will show help)
              :ok
          end

        {:error, _} ->
          # Mission not found, allow (backward compatibility)
          :ok
      end
    end
  end
end
