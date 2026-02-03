defmodule Invader.Connections.Telegram.WebhookHandler do
  @moduledoc """
  Processes incoming Telegram webhook updates.

  Handles two types of messages:
  - `/start <code>` - Chat registration
  - Reply messages - Matches to pending prompts and notifies callers
  """

  alias Invader.Connections.Telegram.{ChatRegistration, Client, PendingPrompt}
  alias Invader.Connections.Connection

  require Logger

  @doc """
  Process an incoming Telegram update.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec handle_update(map()) :: :ok | {:error, term()}
  def handle_update(%{"message" => message}) do
    handle_message(message)
  end

  def handle_update(_update) do
    # Ignore non-message updates (edited messages, channel posts, etc.)
    :ok
  end

  defp handle_message(%{"text" => "/start " <> code} = message) do
    chat_id = get_in(message, ["chat", "id"])
    username = get_in(message, ["from", "username"])

    case ChatRegistration.complete_registration(String.trim(code), chat_id, username) do
      {:ok, _connection} ->
        Logger.info("Telegram chat #{chat_id} registered successfully")
        :ok

      {:error, reason} ->
        Logger.warning("Telegram registration failed: #{inspect(reason)}")
        send_error_message(chat_id, "Registration failed. The code may be invalid or expired.")
        {:error, reason}
    end
  end

  defp handle_message(%{"text" => "/start"} = message) do
    chat_id = get_in(message, ["chat", "id"])

    send_error_message(
      chat_id,
      "Welcome! To connect this chat to Invader, use the link from your Invader settings."
    )

    :ok
  end

  defp handle_message(%{"reply_to_message" => original, "text" => response_text} = message) do
    chat_id = get_in(message, ["chat", "id"])
    original_message_id = original["message_id"]

    handle_reply(chat_id, original_message_id, response_text)
  end

  defp handle_message(_message) do
    # Ignore other messages (photos, stickers, etc.)
    :ok
  end

  defp handle_reply(chat_id, original_message_id, response_text) do
    case PendingPrompt.get_by_message(chat_id, original_message_id) do
      {:ok, prompt} ->
        # Update the prompt with the response
        {:ok, _updated} = PendingPrompt.mark_responded(prompt, response_text)

        # Notify the waiting process
        notify_caller(prompt, response_text)

        Logger.debug("Telegram reply matched prompt #{prompt.id}")
        :ok

      {:error, %Ash.Error.Query.NotFound{}} ->
        # No pending prompt for this message - might be an old message or not a prompt reply
        Logger.debug(
          "No pending prompt found for message #{original_message_id} in chat #{chat_id}"
        )

        :ok

      {:error, reason} ->
        Logger.warning("Error looking up pending prompt: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp notify_caller(%PendingPrompt{caller_pid: caller_pid_binary}, response_text)
       when is_binary(caller_pid_binary) do
    try do
      caller_pid = :erlang.binary_to_term(caller_pid_binary)

      if Process.alive?(caller_pid) do
        send(caller_pid, {:telegram_response, response_text})
      end
    rescue
      ArgumentError ->
        Logger.warning("Invalid caller_pid binary in pending prompt")
    end
  end

  defp notify_caller(_prompt, _response_text), do: :ok

  defp send_error_message(chat_id, text) do
    # Get the telegram connection to send error message
    case Connection.get_by_type(:telegram) do
      {:ok, %{telegram_bot_token: token}} when is_binary(token) ->
        Client.send_message(token, chat_id, text)

      _ ->
        :ok
    end
  end
end
