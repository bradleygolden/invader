defmodule Invader.SpriteCli.Cli do
  @moduledoc """
  Wrapper for interacting with sprites via the Sprites SDK.
  """

  @doc """
  Gets a Sprites client. Reads token from SPRITES_TOKEN env var.
  """
  def client do
    token = System.get_env("SPRITES_TOKEN") || raise "SPRITES_TOKEN not set"
    Sprites.new(token)
  end

  @doc """
  Gets a sprite handle by name.
  """
  def sprite(name) do
    Sprites.sprite(client(), name)
  end

  @doc """
  Lists all available sprites.
  Returns {:ok, list} or {:error, reason}
  """
  def list(opts \\ []) do
    case Sprites.list(client(), opts) do
      {:ok, sprites} ->
        parsed =
          Enum.map(sprites, fn s ->
            %{
              name: s["name"] || s[:name],
              org: s["org"] || s[:org],
              status: parse_status(s["status"] || s[:status])
            }
          end)

        {:ok, parsed}

      error ->
        error
    end
  end

  defp parse_status(nil), do: :unknown
  defp parse_status("running"), do: :available
  defp parse_status("available"), do: :available
  defp parse_status("busy"), do: :busy
  defp parse_status("offline"), do: :offline
  defp parse_status("stopped"), do: :offline
  defp parse_status(_), do: :unknown

  @doc """
  Executes a command inside a sprite.
  """
  def exec(sprite_name, command) when is_binary(command) do
    sprite = sprite(sprite_name)
    {output, exit_code} = Sprites.cmd(sprite, "bash", ["-c", command], stderr_to_stdout: true)

    if exit_code == 0 do
      {:ok, output}
    else
      {:error, {exit_code, output}}
    end
  end

  @doc """
  Opens an interactive console to the sprite (for TTY use).
  Uses spawn with tty: true for interactive sessions.
  """
  def console(sprite_name) do
    sprite = sprite(sprite_name)
    Sprites.spawn(sprite, "bash", ["-i"], tty: true)
  end

  @doc """
  Creates a checkpoint for the sprite.
  """
  def checkpoint_create(sprite_name, comment \\ nil) do
    sprite = sprite(sprite_name)
    opts = if comment, do: [comment: comment], else: []

    case Sprites.create_checkpoint(sprite, opts) do
      {:ok, stream} ->
        # Consume the stream to get the final result
        result = Enum.to_list(stream)

        # Extract checkpoint ID from the stream messages
        checkpoint_id =
          result
          |> Enum.find_value(fn
            %{"checkpoint_id" => id} -> id
            %{checkpoint_id: id} -> id
            %{"id" => id} -> id
            %{id: id} -> id
            _ -> nil
          end)

        if checkpoint_id do
          {:ok, checkpoint_id}
        else
          {:ok, "checkpoint-created"}
        end

      error ->
        error
    end
  end

  @doc """
  Lists checkpoints for a sprite.
  """
  def checkpoint_list(sprite_name) do
    sprite = sprite(sprite_name)

    case Sprites.list_checkpoints(sprite) do
      {:ok, checkpoints} ->
        parsed =
          Enum.map(checkpoints, fn cp ->
            %{
              checkpoint_id: cp.id || cp["id"],
              comment: cp.comment || cp["comment"] || ""
            }
          end)

        {:ok, parsed}

      error ->
        error
    end
  end

  @doc """
  Restores a sprite to a specific checkpoint.
  """
  def restore(sprite_name, checkpoint_id) do
    sprite = sprite(sprite_name)

    case Sprites.restore_checkpoint(sprite, checkpoint_id) do
      {:ok, stream} ->
        # Consume the stream to complete the restore
        _result = Enum.to_list(stream)
        {:ok, "restored"}

      error ->
        error
    end
  end

  @doc """
  Checks if a sprite is available and responding.
  """
  def health_check(sprite_name) do
    case exec(sprite_name, "echo ok") do
      {:ok, output} when output in ["ok\n", "ok"] -> :ok
      {:ok, _} -> {:error, :unexpected_response}
      error -> error
    end
  end

  @doc """
  Gets detailed information about a sprite from the API.
  """
  def get_info(sprite_name) do
    case Sprites.get_sprite(client(), sprite_name) do
      {:ok, info} ->
        {:ok,
         %{
           id: info["id"],
           name: info["name"],
           organization: info["organization"],
           status: info["status"],
           url: info["url"],
           version: info["version"],
           created_at: info["created_at"],
           updated_at: info["updated_at"]
         }}

      error ->
        error
    end
  end

  @doc """
  Gets system metrics (CPU, memory, disk) from a sprite.
  """
  def get_metrics(sprite_name) do
    command = """
    echo "MEM:" && free -b | grep Mem && \
    echo "DISK:" && df -B1 / | tail -1 && \
    echo "CPU:" && nproc && cat /proc/loadavg
    """

    case exec(sprite_name, command) do
      {:ok, output} -> {:ok, parse_metrics(output)}
      error -> error
    end
  end

  defp parse_metrics(output) do
    lines = String.split(output, "\n", trim: true)

    %{
      memory: parse_memory(lines),
      disk: parse_disk(lines),
      cpu: parse_cpu(lines)
    }
  end

  defp parse_memory(lines) do
    case Enum.find_index(lines, &(&1 == "MEM:")) do
      nil ->
        %{total: 0, used: 0, free: 0, available: 0}

      idx ->
        mem_line = Enum.at(lines, idx + 1, "")
        parts = String.split(mem_line, ~r/\s+/, trim: true)

        %{
          total: parse_int(Enum.at(parts, 1, "0")),
          used: parse_int(Enum.at(parts, 2, "0")),
          free: parse_int(Enum.at(parts, 3, "0")),
          available: parse_int(Enum.at(parts, 6, "0"))
        }
    end
  end

  defp parse_disk(lines) do
    case Enum.find_index(lines, &(&1 == "DISK:")) do
      nil ->
        %{total: 0, used: 0, available: 0, percent: 0}

      idx ->
        disk_line = Enum.at(lines, idx + 1, "")
        parts = String.split(disk_line, ~r/\s+/, trim: true)

        %{
          total: parse_int(Enum.at(parts, 1, "0")),
          used: parse_int(Enum.at(parts, 2, "0")),
          available: parse_int(Enum.at(parts, 3, "0")),
          percent: parse_percent(Enum.at(parts, 4, "0%"))
        }
    end
  end

  defp parse_cpu(lines) do
    case Enum.find_index(lines, &(&1 == "CPU:")) do
      nil ->
        %{cores: 0, load_1m: 0.0, load_5m: 0.0, load_15m: 0.0}

      idx ->
        cores = parse_int(Enum.at(lines, idx + 1, "0"))
        load_line = Enum.at(lines, idx + 2, "")
        load_parts = String.split(load_line, ~r/\s+/, trim: true)

        %{
          cores: cores,
          load_1m: parse_float(Enum.at(load_parts, 0, "0")),
          load_5m: parse_float(Enum.at(load_parts, 1, "0")),
          load_15m: parse_float(Enum.at(load_parts, 2, "0"))
        }
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_percent(str) do
    str |> String.replace("%", "") |> parse_int()
  end

  @doc """
  Runs a claude command in a sprite with prompt piped to stdin.
  """
  def run_claude(sprite_name, prompt, opts \\ []) do
    sprite = sprite(sprite_name)

    # Start bash with the claude command
    command = "claude -p --output-format=stream-json"

    case Sprites.spawn(sprite, "bash", ["-c", command]) do
      {:ok, cmd} ->
        # Write prompt to stdin
        :ok = Sprites.write(cmd, prompt)
        :ok = Sprites.close_stdin(cmd)

        # Collect output
        output = collect_output(cmd, opts[:timeout] || :infinity)
        output

      error ->
        error
    end
  end

  defp collect_output(cmd, timeout) do
    collect_output(cmd, timeout, [])
  end

  defp collect_output(cmd, timeout, acc) do
    receive do
      {:stdout, ^cmd, data} ->
        collect_output(cmd, timeout, [data | acc])

      {:stderr, ^cmd, data} ->
        collect_output(cmd, timeout, [data | acc])

      {:exit, ^cmd, exit_code} ->
        output = acc |> Enum.reverse() |> IO.iodata_to_binary()
        {output, exit_code}

      {:error, ^cmd, reason} ->
        {:error, reason}
    after
      timeout ->
        {:error, :timeout}
    end
  end
end
