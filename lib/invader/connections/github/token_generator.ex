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
  Generate an installation access token using an explicit installation_id.

  This allows generating tokens for installations other than the one stored
  in the connection, enabling multi-org support.

  Returns {:ok, %{token: string, expires_at: string}} on success.
  """
  def generate_token(connection, installation_id) do
    with {:ok, jwt} <- create_jwt(connection.app_id, connection.private_key),
         {:ok, token_data} <- request_installation_token(jwt, installation_id) do
      {:ok, token_data}
    end
  end

  @doc """
  Test if the connection credentials are valid.

  If installation_id is configured, attempts to generate a token.
  Otherwise, verifies the app credentials by listing installations.
  """
  def test_connection(connection) do
    if connection.installation_id do
      case generate_token(connection) do
        {:ok, _token_data} -> {:ok, :connected}
        {:error, reason} -> {:error, reason}
      end
    else
      # No installation_id, just verify app credentials work
      case create_jwt(connection.app_id, connection.private_key) do
        {:ok, jwt} -> verify_app_credentials(jwt)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Lists all installations for the GitHub App.

  Returns a list of installation info: %{id: string, owner: string, owner_type: :org | :user}
  """
  def list_installations(connection) do
    with {:ok, jwt} <- create_jwt(connection.app_id, connection.private_key) do
      fetch_all_installations(jwt)
    end
  end

  @doc """
  Lists repositories accessible to a specific installation.

  Returns a list of repo info maps.
  """
  def list_installation_repos(connection, installation_id) do
    with {:ok, %{token: token}} <- generate_token(connection, installation_id) do
      fetch_installation_repos(token)
    end
  end

  defp fetch_all_installations(jwt, page \\ 1, acc \\ []) do
    url = "#{@github_api}/app/installations?per_page=100&page=#{page}"

    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: installations}} when is_list(installations) ->
        parsed =
          Enum.map(installations, fn inst ->
            %{
              id: to_string(inst["id"]),
              owner: get_in(inst, ["account", "login"]),
              owner_type: if(inst["account"]["type"] == "Organization", do: :org, else: :user)
            }
          end)

        if length(installations) == 100 do
          fetch_all_installations(jwt, page + 1, acc ++ parsed)
        else
          {:ok, acc ++ parsed}
        end

      {:ok, %{status: status, body: body}} ->
        message = body["message"] || "Unknown error"
        {:error, "GitHub API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp fetch_installation_repos(token, page \\ 1, acc \\ []) do
    url = "#{@github_api}/installation/repositories?per_page=100&page=#{page}"

    headers = [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"repositories" => repos}}} when is_list(repos) ->
        parsed =
          Enum.map(repos, fn repo ->
            %{
              owner: get_in(repo, ["owner", "login"]) || "",
              name: repo["name"] || "",
              full_name: repo["full_name"] || "",
              description: repo["description"]
            }
          end)

        if length(repos) == 100 do
          fetch_installation_repos(token, page + 1, acc ++ parsed)
        else
          {:ok, acc ++ parsed}
        end

      {:ok, %{status: status, body: body}} ->
        message = body["message"] || "Unknown error"
        {:error, "GitHub API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp verify_app_credentials(jwt) do
    url = "#{@github_api}/app"

    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200}} ->
        {:ok, :connected}

      {:ok, %{status: status, body: body}} ->
        message = body["message"] || "Unknown error"
        {:error, "GitHub API error (#{status}): #{message}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
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
