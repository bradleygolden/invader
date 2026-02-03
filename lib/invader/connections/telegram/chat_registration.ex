defmodule Invader.Connections.Telegram.ChatRegistration do
  @moduledoc """
  Handles linking a user's Telegram account to their Invader connection.

  Registration flow:
  1. User clicks "Connect Telegram" in UI
  2. `start_registration/1` generates a code and returns a deep link
  3. User opens link in Telegram, which opens the bot with `/start <code>`
  4. Webhook receives the message, calls `complete_registration/3`
  5. Connection is updated with chat_id and marked as connected
  """

  alias Invader.Connections.Connection
  alias Invader.Connections.Telegram.{Client, RegistrationStore}

  require Logger

  @doc """
  Start the registration process for a Telegram connection.

  Returns `{:ok, %{code: code, link: link}}` with the registration code
  and a Telegram deep link the user should open.
  """
  @spec start_registration(Connection.t()) :: {:ok, map()} | {:error, term()}
  def start_registration(%Connection{id: id, telegram_bot_token: token} = connection)
      when is_binary(token) do
    # Verify bot token is valid
    case Client.get_me(token) do
      {:ok, %{"username" => bot_username}} ->
        code = RegistrationStore.generate_code(id)
        link = "https://t.me/#{bot_username}?start=#{code}"

        # Generate webhook secret if not already set
        connection =
          if is_nil(connection.telegram_webhook_secret) do
            secret = generate_webhook_secret()
            {:ok, updated} = Connection.update(connection, %{telegram_webhook_secret: secret})
            updated
          else
            connection
          end

        # Set up webhook
        setup_webhook(connection)

        {:ok, %{code: code, link: link, bot_username: bot_username}}

      {:error, reason} ->
        {:error, {:invalid_token, reason}}
    end
  end

  def start_registration(_connection) do
    {:error, :missing_bot_token}
  end

  @doc """
  Complete registration when user sends `/start <code>` to the bot.

  Called by the webhook handler when it receives a start command.
  """
  @spec complete_registration(String.t(), integer(), String.t() | nil) ::
          {:ok, Connection.t()} | {:error, term()}
  def complete_registration(code, chat_id, username) do
    case RegistrationStore.lookup(code) do
      {:ok, connection_id} ->
        case Connection.get(connection_id) do
          {:ok, connection} ->
            {:ok, updated} =
              Connection.update(connection, %{
                telegram_chat_id: chat_id,
                telegram_username: username,
                status: :connected
              })

            RegistrationStore.delete(code)

            # Send welcome message
            send_welcome_message(updated)

            {:ok, updated}

          {:error, _} = error ->
            error
        end

      {:error, :not_found} ->
        {:error, :invalid_or_expired_code}
    end
  end

  @doc """
  Set up the webhook for a Telegram connection.
  """
  @spec setup_webhook(Connection.t()) :: :ok | {:error, term()}
  def setup_webhook(%Connection{telegram_bot_token: token, telegram_webhook_secret: secret})
      when is_binary(token) and is_binary(secret) do
    # Use SPRITE_CALLBACK_URL (cloudflare tunnel) if available, otherwise fall back to endpoint URL
    base_url =
      System.get_env("SPRITE_CALLBACK_URL") || InvaderWeb.Endpoint.url()

    webhook_url = "#{base_url}/webhooks/telegram"

    case Client.set_webhook(token, webhook_url, secret_token: secret) do
      {:ok, _} ->
        Logger.info("Telegram webhook configured: #{webhook_url}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to set Telegram webhook: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def setup_webhook(_connection), do: {:error, :missing_credentials}

  defp send_welcome_message(%Connection{telegram_bot_token: token, telegram_chat_id: chat_id}) do
    message = """
    Connected to Invader!

    You'll receive mission notifications here. When asked a question, just reply to the message.
    """

    Client.send_message(token, chat_id, message)
  end

  defp generate_webhook_secret do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
