defmodule Invader.Accounts.Emails do
  @moduledoc """
  Email delivery for authentication flows.
  """
  import Swoosh.Email

  @doc """
  Sends a magic link email to the user for passwordless authentication.
  """
  def send_magic_link(user_or_email, token) do
    {email_address, name} = extract_email_info(user_or_email)
    url = build_magic_link_url(token)

    new()
    |> to({name, email_address})
    |> from({"Invader", sender_email()})
    |> subject("Sign in to Invader")
    |> text_body("""
    Click the link below to sign in to Invader:

    #{url}

    This link expires in 10 minutes and can only be used once.

    If you didn't request this, you can safely ignore this email.
    """)
    |> Invader.Mailer.deliver()
  end

  defp extract_email_info(user_or_email) when is_binary(user_or_email) do
    {user_or_email, user_or_email}
  end

  defp extract_email_info(user) do
    {user.email, user.name || user.email}
  end

  defp sender_email do
    Application.get_env(:invader, :mailer_from_email, "noreply@invader.local")
  end

  defp build_magic_link_url(token) do
    endpoint = Application.get_env(:invader, InvaderWeb.Endpoint)
    url_config = endpoint[:url] || []
    host = url_config[:host] || "localhost"
    scheme = url_config[:scheme] || if host == "localhost", do: "http", else: "https"
    port = url_config[:port] || endpoint[:http][:port] || 4000

    base =
      if scheme == "https" or port in [80, 443] do
        "#{scheme}://#{host}"
      else
        "#{scheme}://#{host}:#{port}"
      end

    "#{base}/auth/user/magic_link?token=#{token}"
  end
end
