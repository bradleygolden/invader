defmodule Invader.Connections.Telegram.Notifier do
  @moduledoc """
  High-level interface for Telegram notifications.

  Provides two modes of operation:
  - `notify/2` - Fire-and-forget async notifications via Oban
  - `ask/3` - Blocking prompts that wait for user reply

  ## Examples

      # Async notification - returns immediately
      iex> Notifier.notify("Wave 3 complete")
      {:ok, %Oban.Job{}}

      # Blocking prompt - waits for reply
      iex> Notifier.ask("Deploy to prod?", timeout: 60_000)
      {:ok, "yes"}

      # Timeout if no reply
      iex> Notifier.ask("Quick!", timeout: 5_000)
      {:error, :timeout}
  """

  alias Invader.Connections.Connection
  alias Invader.Connections.Telegram.{Client, PendingPrompt}
  alias Invader.Workers.TelegramNotifier

  require Logger

  @default_timeout :timer.minutes(5)

  @doc """
  Send an async notification via Oban.

  Returns immediately after enqueueing the job.

  ## Options
    * `:parse_mode` - "HTML" or "MarkdownV2" for formatted text
  """
  @spec notify(String.t(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def notify(message, opts \\ []) do
    TelegramNotifier.enqueue(message, opts)
  end

  @doc """
  Send a blocking prompt and wait for user reply.

  Uses Telegram's ForceReply markup to prompt the user to reply,
  then blocks until a reply is received or timeout occurs.

  ## Options
    * `:timeout` - Max time to wait in milliseconds (default: 5 minutes)
    * `:mission_id` - Optional mission context for tracking
    * `:parse_mode` - "HTML" or "MarkdownV2" for formatted text

  ## Returns
    * `{:ok, response_text}` - User's reply
    * `{:error, :timeout}` - No reply within timeout
    * `{:error, :not_configured}` - Telegram not connected
    * `{:error, reason}` - Other errors
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    mission_id = opts[:mission_id]

    case get_telegram_connection() do
      {:ok, %{telegram_bot_token: token, telegram_chat_id: chat_id}}
      when is_binary(token) and is_integer(chat_id) ->
        do_ask(token, chat_id, question, timeout, mission_id, opts)

      {:ok, _} ->
        {:error, :not_configured}

      {:error, _} = error ->
        error
    end
  end

  defp do_ask(token, chat_id, question, timeout, mission_id, opts) do
    reply_markup = %{
      "force_reply" => true,
      "selective" => true,
      "input_field_placeholder" => "Type your response..."
    }

    send_opts =
      [reply_markup: reply_markup]
      |> maybe_add(:parse_mode, opts[:parse_mode])

    case Client.send_message(token, chat_id, question, send_opts) do
      {:ok, %{"message_id" => message_id}} ->
        wait_for_reply(chat_id, message_id, timeout, mission_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_reply(chat_id, message_id, timeout, mission_id) do
    timeout_at = DateTime.add(DateTime.utc_now(), timeout, :millisecond)

    # Create pending prompt record
    case PendingPrompt.create(%{
           chat_id: chat_id,
           message_id: message_id,
           caller_pid: :erlang.term_to_binary(self()),
           timeout_at: timeout_at,
           mission_id: mission_id
         }) do
      {:ok, prompt} ->
        # Wait for response
        receive do
          {:telegram_response, response_text} ->
            {:ok, response_text}
        after
          timeout ->
            # Mark as timed out
            PendingPrompt.mark_timeout(prompt)
            {:error, :timeout}
        end

      {:error, reason} ->
        Logger.error("Failed to create pending prompt: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_telegram_connection do
    Connection.get_by_type(:telegram)
  end

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: Keyword.put(list, key, value)
end
