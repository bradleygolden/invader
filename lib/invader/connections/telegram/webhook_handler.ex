defmodule Invader.Connections.Telegram.WebhookHandler do
  @moduledoc """
  Processes incoming Telegram webhook updates.

  Handles three types of updates:
  - `/start <code>` - Chat registration
  - Reply messages - Matches to pending prompts and notifies callers
  - Callback queries - Handles inline button presses for approvals
  """

  alias Invader.Approvals.{Enforcer, PendingApproval}
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

  def handle_update(%{"callback_query" => callback_query}) do
    handle_callback_query(callback_query)
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

  # Handle callback queries from inline keyboard buttons (approve/deny)
  defp handle_callback_query(%{"id" => query_id, "data" => data, "from" => from} = query) do
    username = from["username"] || from["first_name"] || "unknown"
    decided_by = "telegram:@#{username}"

    case parse_callback_data(data) do
      {:approve, callback_data} ->
        handle_approval_decision(query_id, query, callback_data, :approved, decided_by)

      {:deny, callback_data} ->
        handle_approval_decision(query_id, query, callback_data, :denied, decided_by)

      :unknown ->
        Logger.warning("Unknown callback data: #{data}")
        answer_callback(query_id, "Unknown action")
        :ok
    end
  end

  defp handle_callback_query(_query) do
    :ok
  end

  defp parse_callback_data("approve:" <> callback_data), do: {:approve, callback_data}
  defp parse_callback_data("deny:" <> callback_data), do: {:deny, callback_data}
  defp parse_callback_data(_), do: :unknown

  defp handle_approval_decision(query_id, query, callback_data, decision, decided_by) do
    case PendingApproval.get_pending_by_callback_data(callback_data) do
      {:ok, approval} ->
        # Notify the waiting process
        case Enforcer.notify_decision(approval, decision, decided_by) do
          :ok ->
            # Answer the callback and update the message
            decision_text = if decision == :approved, do: "APPROVED", else: "DENIED"
            decision_emoji = if decision == :approved, do: "✓", else: "✗"

            answer_callback(query_id, "#{decision_emoji} #{decision_text}")
            update_approval_message(query, decision, decided_by)

            Logger.info("Approval #{approval.id} #{decision} by #{decided_by}")
            :ok

          {:error, reason} ->
            Logger.warning("Failed to notify decision: #{inspect(reason)}")
            answer_callback(query_id, "Error processing decision")
            {:error, reason}
        end

      {:error, %Ash.Error.Query.NotFound{}} ->
        Logger.warning("No pending approval found for callback: #{callback_data}")
        answer_callback(query_id, "This approval has expired or was already handled")
        :ok

      {:error, reason} ->
        Logger.warning("Error looking up approval: #{inspect(reason)}")
        answer_callback(query_id, "Error looking up approval")
        {:error, reason}
    end
  end

  defp answer_callback(query_id, text) do
    case Connection.get_by_type(:telegram) do
      {:ok, %{telegram_bot_token: token}} when is_binary(token) ->
        Client.answer_callback_query(token, query_id, text: text)

      _ ->
        :ok
    end
  end

  defp update_approval_message(query, decision, decided_by) do
    chat_id = get_in(query, ["message", "chat", "id"])
    message_id = get_in(query, ["message", "message_id"])
    original_text = get_in(query, ["message", "text"]) || ""

    decision_text = if decision == :approved, do: "✓ APPROVED", else: "✗ DENIED"

    # Update the message to show the decision
    new_text = """
    #{original_text}

    #{decision_text} by #{decided_by}
    """

    case Connection.get_by_type(:telegram) do
      {:ok, %{telegram_bot_token: token}} when is_binary(token) ->
        # Remove the inline keyboard and update text
        Client.edit_message_text(token, chat_id, message_id, new_text, reply_markup: nil)

      _ ->
        :ok
    end
  end
end
