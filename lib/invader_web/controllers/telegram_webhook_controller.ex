defmodule InvaderWeb.TelegramWebhookController do
  @moduledoc """
  Handles incoming Telegram webhook requests.

  Verifies the secret token header and delegates to the WebhookHandler.
  """
  use InvaderWeb, :controller

  alias Invader.Connections.Connection
  alias Invader.Connections.Telegram.WebhookHandler

  require Logger

  @doc """
  Handle incoming Telegram webhook updates.

  Telegram sends updates as POST requests with JSON body.
  The X-Telegram-Bot-Api-Secret-Token header must match our stored secret.
  """
  def handle(conn, params) do
    with :ok <- verify_secret_token(conn),
         :ok <- WebhookHandler.handle_update(params) do
      json(conn, %{ok: true})
    else
      {:error, :invalid_secret} ->
        Logger.warning("Telegram webhook request with invalid secret token")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid secret token"})

      {:error, reason} ->
        Logger.error("Telegram webhook handler error: #{inspect(reason)}")

        # Always return 200 OK to Telegram to acknowledge receipt and stop retries
        # Application-level errors are logged but don't cause Telegram to retry
        json(conn, %{ok: true})
    end
  end

  defp verify_secret_token(conn) do
    received_secret = get_req_header(conn, "x-telegram-bot-api-secret-token") |> List.first()

    case Connection.get_by_type(:telegram) do
      {:ok, %{telegram_webhook_secret: expected_secret}}
      when is_binary(expected_secret) and expected_secret != "" ->
        if Plug.Crypto.secure_compare(received_secret || "", expected_secret) do
          :ok
        else
          {:error, :invalid_secret}
        end

      _ ->
        # No telegram connection or no secret configured - reject all requests
        {:error, :invalid_secret}
    end
  end
end
