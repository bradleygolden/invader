defmodule Invader.Connections.Telegram.Client do
  @moduledoc """
  Minimal Telegram Bot API client using Req.

  Provides low-level API methods for sending messages, managing webhooks,
  and validating bot tokens.
  """

  @base_url "https://api.telegram.org/bot"

  @doc """
  Send a message to a chat.

  ## Options
    * `:parse_mode` - "HTML" or "MarkdownV2" for formatted text
    * `:reply_markup` - keyboard markup (e.g., ForceReply)
  """
  def send_message(token, chat_id, text, opts \\ []) do
    body =
      %{chat_id: chat_id, text: text}
      |> maybe_add(:parse_mode, opts[:parse_mode])
      |> maybe_add(:reply_markup, opts[:reply_markup])

    post(token, "sendMessage", body)
  end

  @doc """
  Configure webhook URL for receiving updates.

  ## Options
    * `:secret_token` - secret token to verify webhook requests
  """
  def set_webhook(token, url, opts \\ []) do
    body =
      %{url: url}
      |> maybe_add(:secret_token, opts[:secret_token])

    post(token, "setWebhook", body)
  end

  @doc """
  Remove webhook configuration.
  """
  def delete_webhook(token) do
    post(token, "deleteWebhook", %{})
  end

  @doc """
  Get bot information to validate the token.
  """
  def get_me(token) do
    get(token, "getMe")
  end

  @doc """
  Send a document to a chat.

  ## Parameters
    * `token` - Bot token
    * `chat_id` - Target chat ID
    * `file_binary` - The file content as binary
    * `opts` - Options:
      * `:filename` - Name for the file (required)
      * `:caption` - Optional caption for the document (max 1024 chars)
      * `:content_type` - MIME type (default: "application/octet-stream")

  ## Returns
    * `{:ok, message}` - The sent message object
    * `{:error, reason}` - Error description
  """
  def send_document(token, chat_id, file_binary, opts \\ []) do
    filename = Keyword.fetch!(opts, :filename)
    caption = Keyword.get(opts, :caption)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    fields =
      [
        {"chat_id", to_string(chat_id)},
        {"document", {file_binary, filename: filename, content_type: content_type}}
      ]
      |> maybe_add_multipart_field("caption", caption)

    post_multipart(token, "sendDocument", fields)
  end

  defp post(token, method, body) do
    Req.post("#{@base_url}#{token}/#{method}", json: body)
    |> handle_response()
  end

  defp post_multipart(token, method, fields) do
    Req.post("#{@base_url}#{token}/#{method}", form_multipart: fields)
    |> handle_response()
  end

  defp get(token, method) do
    Req.get("#{@base_url}#{token}/#{method}")
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: %{"ok" => true, "result" => result}}}) do
    {:ok, result}
  end

  defp handle_response({:ok, %{body: %{"ok" => false, "description" => desc}}}) do
    {:error, desc}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_multipart_field(fields, _key, nil), do: fields
  defp maybe_add_multipart_field(fields, key, value), do: fields ++ [{key, value}]
end
