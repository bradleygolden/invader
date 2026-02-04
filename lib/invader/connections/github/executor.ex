defmodule Invader.Connections.GitHub.Executor do
  @moduledoc """
  Executes GitHub CLI commands either by proxying through the server
  or by returning an ephemeral token for local execution.

  ## Modes

  - `:proxy` - Server executes the command and returns output.
    Used for stateless operations like `gh pr list`, `gh issue view`.

  - `:token` - Returns an ephemeral token for local execution.
    Used for stateful operations like `gh repo clone`, `git push`.

  The mode is automatically determined based on the command, but can
  be explicitly specified.
  """

  alias Invader.Connections.GitHub.InstallationResolver
  alias Invader.Connections.GitHub.TokenGenerator
  alias Invader.Connections.Request
  alias Invader.Scopes.Parsers.GitHub, as: GitHubParser

  @stateful_commands ~w(clone checkout push pull fetch)

  require Logger

  @doc """
  List repositories accessible via the GitHub connection.

  Uses the GitHub API to list repos from ALL installations where the app is installed.
  This allows multi-org support without requiring a pre-configured installation_id.

  ## Options

  - `:limit` - Maximum number of repos to return (default: 100)

  ## Returns

    {:ok, [%{owner: string, name: string, full_name: string, description: string | nil}]}
  """
  def list_repos(connection, opts \\ []) do
    limit = opts[:limit] || 100

    with {:ok, installations} <- TokenGenerator.list_installations(connection) do
      repos =
        installations
        |> Task.async_stream(
          fn inst ->
            case TokenGenerator.list_installation_repos(connection, inst.id) do
              {:ok, repos} -> repos
              {:error, reason} ->
                Logger.warning("Failed to list repos for installation #{inst.id}: #{inspect(reason)}")
                []
            end
          end,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, repos} -> repos
          {:exit, _} -> []
        end)
        |> Enum.uniq_by(& &1.full_name)
        |> Enum.sort_by(& &1.full_name)
        |> Enum.take(limit)

      {:ok, repos}
    end
  end

  @doc """
  Execute a GitHub CLI command.

  ## Options

  - `:mode` - Force a specific mode (`:proxy` or `:token`). Auto-detected if not specified.
  - `:sprite_id` - ID of the sprite making the request (for audit trail).

  ## Returns

  For proxy mode:
    {:ok, %{mode: :proxy, output: string}}

  For token mode:
    {:ok, %{mode: :token, token: string, expires_at: string}}

  On error:
    {:error, %{exit_code: integer, output: string}} or {:error, string}
  """
  def execute(connection, args, opts \\ []) do
    mode = opts[:mode] || determine_mode(args)
    sprite_id = opts[:sprite_id]
    command = Enum.join(args, " ")

    start_time = System.monotonic_time(:millisecond)

    result =
      case mode do
        :proxy -> execute_proxied(connection, args)
        :token -> return_token(connection, args)
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Create audit trail
    log_request(connection, sprite_id, command, mode, result, duration_ms)

    result
  end

  @doc """
  Determine the execution mode based on the command arguments.

  Commands that require local filesystem access (clone, push, etc.)
  use token mode. All others use proxy mode.
  """
  def determine_mode(args) do
    cmd_string = Enum.join(args, " ")

    if Enum.any?(@stateful_commands, &String.contains?(cmd_string, &1)) do
      :token
    else
      :proxy
    end
  end

  defp execute_proxied(connection, args) do
    with {:ok, %{token: token}} <- generate_token_for_args(connection, args) do
      command = "gh #{Enum.join(args, " ")}"
      env = [{"GH_TOKEN", token}]

      case System.cmd("bash", ["-c", command], env: env, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, %{mode: :proxy, output: String.trim(output)}}

        {output, code} ->
          {:error, %{exit_code: code, output: String.trim(output)}}
      end
    end
  end

  defp return_token(connection, args) do
    case generate_token_for_args(connection, args) do
      {:ok, %{token: token, expires_at: expires_at}} ->
        {:ok, %{mode: :token, token: token, expires_at: expires_at}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Generate token using dynamic installation lookup if repo is specified in args
  defp generate_token_for_args(connection, args) do
    case GitHubParser.extract_repo(args) do
      {:ok, {owner, _repo}} ->
        # Resolve installation_id for this owner
        with {:ok, installation_id} <- InstallationResolver.resolve(connection, owner) do
          TokenGenerator.generate_token(connection, installation_id)
        end

      :error ->
        # No repo specified, use default installation_id (if configured)
        if connection.installation_id do
          TokenGenerator.generate_token(connection)
        else
          {:error, "No --repo flag provided and no default installation_id configured"}
        end
    end
  end

  defp log_request(connection, sprite_id, command, mode, result, duration_ms) do
    {status, result_map} =
      case result do
        {:ok, data} -> {:completed, data}
        {:error, data} when is_map(data) -> {:failed, data}
        {:error, msg} -> {:failed, %{error: msg}}
      end

    Request.create(%{
      connection_id: connection.id,
      sprite_id: sprite_id,
      command: command,
      mode: mode,
      status: status,
      result: result_map,
      duration_ms: duration_ms
    })
  end
end
