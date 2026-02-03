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

  Handles different actions:
  - `"gh"` - GitHub CLI commands
  - `"telegram"` - Telegram operations (ask, notify, send_document)

  ## GitHub Request

      {
        "action": "gh",
        "input": {
          "args": ["pr", "list", "--repo", "owner/repo"],
          "mode": "proxy",  // optional, auto-detected if not specified
          "connection_id": "uuid"  // optional, uses first github connection if not specified
        }
      }

  ## Telegram Request

      {
        "action": "telegram",
        "input": {
          "operation": "ask" | "notify" | "send_document",
          "message": "...",  // for ask/notify
          "file_path": "...",  // for send_document
          "caption": "..."  // optional, for send_document
        }
      }
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

  def run(conn, %{"action" => "telegram", "input" => input}) do
    alias Invader.Scopes.Parsers.Telegram, as: TelegramParser

    case verify_sprite_token(conn) do
      {:ok, claims} ->
        operation = input["operation"]
        mission_id = claims[:mission_id]

        # Check scope permission for Telegram operations
        case check_telegram_scope_permission(claims, operation) do
          :ok ->
            execute_telegram_operation(conn, operation, input, mission_id)

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

  defp execute_telegram_operation(conn, operation, input, mission_id) do
    alias Invader.Connections.Telegram.Notifier

    message = input["message"]
    timeout = input["timeout"]

    case operation do
      "ask" when is_binary(message) ->
        opts = if mission_id, do: [mission_id: mission_id], else: []
        opts = if timeout, do: Keyword.put(opts, :timeout, timeout), else: opts

        case Notifier.ask(message, opts) do
          {:ok, response} ->
            json(conn, %{response: response})

          {:error, :timeout} ->
            conn
            |> put_status(408)
            |> json(%{error: "timeout", message: "No response received within timeout"})

          {:error, :not_configured} ->
            conn
            |> put_status(503)
            |> json(%{error: "not_configured", message: "Telegram not connected"})

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: inspect(reason)})
        end

      "notify" when is_binary(message) ->
        case Notifier.notify(message) do
          {:ok, _job} ->
            json(conn, %{status: "queued"})

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: inspect(reason)})
        end

      "send_document" ->
        file_content = input["file_content"]
        filename = input["filename"]
        caption = input["caption"]

        case {file_content, filename} do
          {content, name} when is_binary(content) and is_binary(name) ->
            case Base.decode64(content) do
              {:ok, file_binary} ->
                opts = if caption, do: [caption: caption], else: []

                case Notifier.send_document(file_binary, filename, opts) do
                  {:ok, _message} ->
                    json(conn, %{status: "sent"})

                  {:error, :not_configured} ->
                    conn
                    |> put_status(503)
                    |> json(%{error: "not_configured", message: "Telegram not connected"})

                  {:error, reason} ->
                    conn
                    |> put_status(500)
                    |> json(%{error: inspect(reason)})
                end

              :error ->
                conn
                |> put_status(400)
                |> json(%{error: "Invalid file_content: must be base64 encoded"})
            end

          _ ->
            conn
            |> put_status(400)
            |> json(%{error: "send_document requires 'file_content' (base64) and 'filename'"})
        end

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid operation. Use 'ask', 'notify', or 'send_document'"})
    end
  end

  defp check_telegram_scope_permission(claims, operation) do
    alias Invader.Scopes.Parsers.Telegram, as: TelegramParser

    mission_id = claims[:mission_id]

    # If no mission_id in token, allow (backward compatibility)
    if is_nil(mission_id) do
      :ok
    else
      case Mission.get(mission_id) do
        {:ok, mission} ->
          # Load scope_preset if needed
          mission = Ash.load!(mission, :scope_preset)

          case TelegramParser.parse_operation(operation) do
            {:ok, scope} ->
              if Checker.allowed?(mission, scope) do
                :ok
              else
                {:error, :forbidden, scope}
              end

            {:error, :no_operation} ->
              # No operation specified, allow (will show error later)
              :ok
          end

        {:error, _} ->
          # Mission not found, allow (backward compatibility)
          :ok
      end
    end
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
