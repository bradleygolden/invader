defmodule Invader.Workers.TelegramNotifier do
  @moduledoc """
  Oban worker for sending async Telegram notifications.

  Used by `Notifier.notify/2` to fire-and-forget notifications
  without blocking the calling process.
  """
  use Oban.Worker,
    queue: :notifications,
    max_attempts: 3

  alias Invader.Connections.Connection
  alias Invader.Connections.Telegram.Client

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message" => message} = args}) do
    opts = [
      parse_mode: args["parse_mode"]
    ]

    case get_telegram_connection() do
      {:ok, %{telegram_bot_token: token, telegram_chat_id: chat_id}}
      when is_binary(token) and is_integer(chat_id) ->
        case Client.send_message(token, chat_id, message, opts) do
          {:ok, _result} ->
            Logger.debug("Telegram notification sent successfully")
            :ok

          {:error, reason} ->
            Logger.error("Failed to send Telegram notification: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, _connection} ->
        Logger.warning("Telegram connection not fully configured (missing token or chat_id)")
        {:error, :not_configured}

      {:error, _} ->
        Logger.warning("No Telegram connection found")
        {:error, :not_configured}
    end
  end

  defp get_telegram_connection do
    Connection.get_by_type(:telegram)
  end

  @doc """
  Enqueue a notification to be sent asynchronously.
  """
  @spec enqueue(String.t(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(message, opts \\ []) do
    args =
      %{"message" => message}
      |> maybe_add("parse_mode", opts[:parse_mode])

    args
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
