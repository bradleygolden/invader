defmodule Invader.Secrets do
  use AshAuthentication.Secret

  @impl true
  def secret_for([:authentication, :strategies, :github, :client_id], _resource, _opts, _context) do
    get_config(:github_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :github, :client_secret],
        _resource,
        _opts,
        _context
      ) do
    get_config(:github_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :github, :redirect_uri],
        _resource,
        _opts,
        _context
      ) do
    get_config(:github_redirect_uri)
  end

  defp get_config(key) do
    case Application.get_env(:invader, key) do
      nil -> {:error, "Missing configuration for #{key}"}
      value -> {:ok, value}
    end
  end
end
