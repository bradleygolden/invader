defmodule Invader.Connections.GitHub.InstallationResolver do
  @moduledoc """
  Resolves GitHub App installation_id for a given owner (org or user).

  GitHub Apps have one app_id + private_key but different installation_ids per org/user.
  This module looks up and caches the installation_id for each owner using the GitHub API.

  ## How it works

  1. Check the in-memory cache for the owner
  2. If miss, call the GitHub API with JWT auth to get the installation_id
  3. Cache the result and return

  The cache is an Agent holding a map: %{owner => installation_id}
  """

  use Agent

  require Logger

  @github_api "https://api.github.com"

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Resolves the installation_id for a given owner (org or user).

  Uses cached value if available, otherwise looks it up via GitHub API.

  ## Parameters

  - `connection` - The GitHub connection with app_id and private_key
  - `owner` - The GitHub org or user name

  ## Returns

  - `{:ok, installation_id}` on success
  - `{:error, reason}` on failure
  """
  def resolve(connection, owner) do
    case get_cached(owner) do
      {:ok, installation_id} ->
        {:ok, installation_id}

      :miss ->
        with {:ok, jwt} <- create_jwt(connection.app_id, connection.private_key),
             {:ok, installation_id} <- lookup_installation(jwt, owner) do
          cache_installation(owner, installation_id)
          {:ok, installation_id}
        end
    end
  end

  @doc """
  Clears the installation cache. Useful for testing or when installations change.
  """
  def clear_cache do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @doc """
  Removes a specific owner from the cache.
  """
  def invalidate(owner) do
    Agent.update(__MODULE__, fn cache -> Map.delete(cache, owner) end)
  end

  defp get_cached(owner) do
    case Agent.get(__MODULE__, fn cache -> Map.fetch(cache, owner) end) do
      {:ok, installation_id} -> {:ok, installation_id}
      :error -> :miss
    end
  end

  defp cache_installation(owner, installation_id) do
    Agent.update(__MODULE__, fn cache -> Map.put(cache, owner, installation_id) end)
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

  defp lookup_installation(jwt, owner) do
    # Try org endpoint first, fall back to user endpoint
    case get_org_installation(jwt, owner) do
      {:ok, installation_id} ->
        {:ok, installation_id}

      {:error, :not_found} ->
        get_user_installation(jwt, owner)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_org_installation(jwt, owner) do
    url = "#{@github_api}/orgs/#{owner}/installation"
    fetch_installation(jwt, url)
  end

  defp get_user_installation(jwt, owner) do
    url = "#{@github_api}/users/#{owner}/installation"
    fetch_installation(jwt, url)
  end

  defp fetch_installation(jwt, url) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"id" => installation_id}}} ->
        {:ok, to_string(installation_id)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        message = body["message"] || "Unknown error"
        Logger.warning("GitHub installation lookup failed (#{status}): #{message}")
        {:error, "GitHub API error (#{status}): #{message}"}

      {:error, reason} ->
        Logger.error("HTTP request failed for installation lookup: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
