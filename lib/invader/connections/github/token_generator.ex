defmodule Invader.Connections.GitHub.TokenGenerator do
  @moduledoc """
  Generates GitHub App installation tokens using JWT authentication.

  GitHub Apps use a two-step authentication process:
  1. Create a JWT signed with the App's private key
  2. Exchange the JWT for an installation access token

  The installation token is valid for 1 hour and grants access to
  repositories where the App is installed.
  """

  @github_api "https://api.github.com"

  @doc """
  Generate an installation access token for the given connection.

  Returns {:ok, %{token: string, expires_at: string}} on success.
  """
  def generate_token(connection) do
    with {:ok, jwt} <- create_jwt(connection.app_id, connection.private_key),
         {:ok, token_data} <- request_installation_token(jwt, connection.installation_id) do
      {:ok, token_data}
    end
  end

  @doc """
  Test if the connection credentials are valid by attempting to generate a token.
  """
  def test_connection(connection) do
    case generate_token(connection) do
      {:ok, _token_data} -> {:ok, :connected}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_jwt(app_id, private_key) do
    now = System.system_time(:second)

    claims = %{
      "iat" => now - 60,
      "exp" => now + 600,
      "iss" => app_id
    }

    signer = Joken.Signer.create("RS256", %{"pem" => private_key})

    case Joken.encode_and_sign(claims, signer) do
      {:ok, jwt, _claims} -> {:ok, jwt}
      {:error, reason} -> {:error, "JWT creation failed: #{inspect(reason)}"}
    end
  end

  defp request_installation_token(jwt, installation_id) do
    url = "#{@github_api}/app/installations/#{installation_id}/access_tokens"

    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case Req.post(url, headers: headers) do
      {:ok, %{status: 201, body: %{"token" => token, "expires_at" => expires_at}}} ->
        {:ok, %{token: token, expires_at: expires_at}}

      {:ok, %{status: status, body: body}} ->
        message = body["message"] || "Unknown error"
        {:error, "GitHub API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
