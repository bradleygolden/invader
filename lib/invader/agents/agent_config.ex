defmodule Invader.Agents.AgentConfig do
  @moduledoc """
  Configuration for supported coding agents.

  Defines agent types (Claude Code, Gemini CLI, OpenAI Codex, custom) and
  provider configurations (Anthropic, z.ai, Google, OpenAI, custom) with
  environment variable mappings for API key injection.
  """

  @agents %{
    claude_code: %{
      name: "Claude Code",
      command: "claude -p --verbose --output-format=stream-json",
      auth_hint: "Run `claude` then `/login` to authenticate",
      providers: [:anthropic_subscription, :anthropic_api, :zai]
    }
  }

  @providers %{
    anthropic_subscription: %{
      name: "Anthropic (Subscription)",
      description: "Use your Claude subscription - login via console",
      env_vars: [],
      requires_api_key: false,
      key_placeholder: nil
    },
    anthropic_api: %{
      name: "Anthropic (API Key)",
      description: "Use an Anthropic API key directly",
      env_vars: [{"ANTHROPIC_API_KEY", :api_key}],
      requires_api_key: true,
      key_placeholder: "sk-ant-..."
    },
    zai: %{
      name: "Z.ai",
      description: "Use Z.ai proxy for Anthropic API",
      env_vars: [
        {"ANTHROPIC_AUTH_TOKEN", :api_key},
        {"ANTHROPIC_BASE_URL", "https://api.z.ai/api/anthropic"},
        {"API_TIMEOUT_MS", "3000000"}
      ],
      requires_api_key: true,
      key_placeholder: "Z.ai API token"
    }
  }

  @type agent_type :: :claude_code
  @type provider :: :anthropic_subscription | :anthropic_api | :zai

  @doc """
  Returns the configuration for a specific agent type.
  """
  @spec get_agent(agent_type()) :: map() | nil
  def get_agent(type) when is_atom(type), do: Map.get(@agents, type)

  @doc """
  Returns the configuration for a specific provider.
  """
  @spec get_provider(provider()) :: map() | nil
  def get_provider(provider) when is_atom(provider), do: Map.get(@providers, provider)

  @doc """
  Returns all available agent configurations.
  """
  @spec list_agents() :: map()
  def list_agents, do: @agents

  @doc """
  Returns all available provider configurations.
  """
  @spec list_providers() :: map()
  def list_providers, do: @providers

  @doc """
  Returns agent types as options for select inputs.
  """
  @spec agent_options() :: [{String.t(), atom()}]
  def agent_options do
    @agents
    |> Enum.map(fn {key, config} -> {config.name, key} end)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  @doc """
  Returns provider types as options for select inputs.
  """
  @spec provider_options() :: [{String.t(), atom()}]
  def provider_options do
    @providers
    |> Enum.map(fn {key, config} -> {config.name, key} end)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  @doc """
  Returns providers available for a specific agent type.
  """
  @spec providers_for_agent(agent_type()) :: [{String.t(), atom()}]
  def providers_for_agent(agent_type) do
    case get_agent(agent_type) do
      nil ->
        []

      config ->
        config.providers
        |> Enum.map(fn p -> {get_provider(p).name, p} end)
    end
  end

  @doc """
  Returns the command to run for a mission.

  Uses the mission's custom agent_command if set, otherwise falls back
  to the default command for the agent type.
  """
  @spec command_for(map()) :: String.t() | nil
  def command_for(%{agent_command: command}) when is_binary(command) and command != "" do
    command
  end

  def command_for(%{agent_type: type}) when not is_nil(type) do
    case get_agent(type) do
      nil -> nil
      config -> config.command
    end
  end

  def command_for(_), do: "claude -p --verbose --output-format=stream-json"

  @doc """
  Builds environment variable pairs for a provider and API key.

  Returns a list of {env_var_name, value} tuples suitable for injection.

  ## Options

    * `:base_url` - Custom base URL for custom providers

  ## Examples

      iex> env_vars_for(:anthropic, "sk-ant-123")
      [{"ANTHROPIC_API_KEY", "sk-ant-123"}]

      iex> env_vars_for(:zai, "zai-token-123")
      [
        {"ANTHROPIC_AUTH_TOKEN", "zai-token-123"},
        {"ANTHROPIC_BASE_URL", "https://api.z.ai/api/anthropic"},
        {"API_TIMEOUT_MS", "3000000"}
      ]
  """
  @spec env_vars_for(provider(), String.t(), keyword()) :: [{String.t(), String.t()}]
  def env_vars_for(provider, api_key, opts \\ []) do
    base_url = Keyword.get(opts, :base_url)
    config = get_provider(provider)

    if config do
      Enum.map(config.env_vars, fn
        {key, :api_key} -> {key, api_key}
        {key, :base_url} -> {key, base_url || ""}
        {key, value} -> {key, value}
      end)
    else
      []
    end
  end

  @doc """
  Returns the authentication hint for an agent type.
  """
  @spec auth_hint_for(agent_type()) :: String.t()
  def auth_hint_for(agent_type) do
    case get_agent(agent_type) do
      nil -> "Configure your agent manually"
      config -> config.auth_hint
    end
  end

  @doc """
  Returns all valid agent types.
  """
  @spec valid_agent_types() :: [agent_type()]
  def valid_agent_types, do: Map.keys(@agents)

  @doc """
  Returns all valid provider types.
  """
  @spec valid_providers() :: [provider()]
  def valid_providers, do: Map.keys(@providers)

  @doc """
  Returns all valid sprite lifecycle options.
  """
  @spec valid_lifecycles() :: [atom()]
  def valid_lifecycles, do: [:keep, :destroy_on_complete, :destroy_on_delete]

  @doc """
  Returns lifecycle options for select inputs.
  """
  @spec lifecycle_options() :: [{String.t(), atom()}]
  def lifecycle_options do
    [
      {"Keep (never auto-destroy)", :keep},
      {"Destroy on successful completion", :destroy_on_complete},
      {"Destroy when mission is deleted", :destroy_on_delete}
    ]
  end
end
