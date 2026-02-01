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

  alias Invader.Connections.GitHub.TokenGenerator
  alias Invader.Connections.Request

  @stateful_commands ~w(clone checkout push pull fetch)

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
        :token -> return_token(connection)
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
    with {:ok, %{token: token}} <- TokenGenerator.generate_token(connection) do
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

  defp return_token(connection) do
    case TokenGenerator.generate_token(connection) do
      {:ok, %{token: token, expires_at: expires_at}} ->
        {:ok, %{mode: :token, token: token, expires_at: expires_at}}

      {:error, reason} ->
        {:error, reason}
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
