defmodule Invader.Workers.LoopRunner do
  @moduledoc """
  Oban worker that executes mission waves.

  Picks up missions from the queue and runs iterations until:
  - max_waves is reached
  - max_duration is exceeded
  - mission is completed/aborted
  - a failure occurs
  """
  use Oban.Worker,
    queue: :missions,
    max_attempts: 3

  require Logger

  alias Invader.Missions
  alias Invader.Missions.{Mission, Wave}
  alias Invader.SpriteCli.Cli

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mission_id" => mission_id}}) do
    with {:ok, mission} <- Missions.Mission.get(mission_id),
         :ok <- validate_can_run(mission) do
      run_wave(mission)
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        Logger.error("Mission #{mission_id} not found")
        {:error, :mission_not_found}

      {:error, reason} ->
        Logger.error("Cannot run mission #{mission_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_can_run(%Mission{status: :running} = mission) do
    if mission.current_wave >= mission.max_waves do
      {:error, :max_waves_reached}
    else
      :ok
    end
  end

  defp validate_can_run(%Mission{status: status}) do
    {:error, {:invalid_status, status}}
  end

  defp run_wave(mission) do
    wave_number = mission.current_wave + 1
    Logger.info("Starting wave #{wave_number} for mission #{mission.id}")

    # Record wave start
    {:ok, wave} =
      Wave.record(%{
        mission_id: mission.id,
        number: wave_number
      })

    # Get prompt - either from file (refreshed each wave) or inline
    prompt = get_prompt(mission)

    # Execute the wave
    {output, exit_code} = execute_wave(mission, prompt)

    # Update wave with results
    {:ok, _wave} =
      Wave.finish(wave, %{
        output: truncate_output(output),
        exit_code: exit_code
      })

    # Update mission's current wave
    handle_wave_result(mission, wave_number, exit_code, output)
  end

  defp get_prompt(%{prompt: prompt}) when is_binary(prompt) and prompt != "" do
    # Inline prompt - use directly
    prompt
  end

  defp get_prompt(%{prompt_path: path}) when is_binary(path) do
    # File-based prompt - read fresh each wave
    case File.read(path) do
      {:ok, content} ->
        content

      {:error, reason} ->
        Logger.warning("Failed to read prompt at #{path}: #{inspect(reason)}")
        ""
    end
  end

  defp get_prompt(_) do
    Logger.warning("No prompt found for mission")
    ""
  end

  defp execute_wave(mission, prompt) do
    sprite = Ash.load!(mission, :sprite).sprite

    # Build the claude command with prompt piped in
    command = build_claude_command(prompt)

    case Cli.exec(sprite.name, command) do
      {:ok, output} -> {output, 0}
      {:error, {code, output}} -> {output, code}
    end
  end

  defp build_claude_command(prompt) do
    # Escape the prompt for shell
    escaped_prompt = prompt |> String.replace("'", "'\\''")
    "echo '#{escaped_prompt}' | claude -p"
  end

  defp handle_wave_result(mission, wave_number, exit_code, _output) do
    cond do
      exit_code != 0 ->
        Logger.error("Wave #{wave_number} failed with exit code #{exit_code}")
        Mission.fail(mission, %{error_message: "Exit code: #{exit_code}"})
        maybe_start_next_pending()
        {:error, :wave_failed}

      wave_number >= mission.max_waves ->
        Logger.info("Mission #{mission.id} completed after #{wave_number} waves")
        Mission.complete(mission)
        maybe_start_next_pending()
        {:ok, :completed}

      true ->
        # Update current_wave and schedule next wave
        schedule_next_wave(mission, wave_number)
    end
  end

  defp maybe_start_next_pending do
    if Invader.Settings.auto_start_queue?() do
      # Find highest priority pending mission
      pending =
        Mission.list!()
        |> Enum.filter(&(&1.status == :pending))
        |> Enum.sort_by(& &1.priority, :desc)
        |> List.first()

      if pending do
        Logger.info("Auto-starting next pending mission: #{pending.id}")
        Mission.start(pending)
        enqueue(pending.id)
      end
    end
  end

  defp schedule_next_wave(mission, wave_number) do
    # Update current wave count
    mission
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.change_attribute(:current_wave, wave_number)
    |> Ash.update!()

    # Create checkpoint between waves
    create_checkpoint(mission, wave_number)

    # Schedule next wave with a small delay
    %{mission_id: mission.id}
    |> __MODULE__.new(schedule_in: 10)
    |> Oban.insert!()

    {:ok, :scheduled_next}
  end

  defp create_checkpoint(mission, wave_number) do
    sprite = Ash.load!(mission, :sprite).sprite
    comment = "wave-#{wave_number}"

    case Cli.checkpoint_create(sprite.name, comment) do
      {:ok, checkpoint_id} ->
        Invader.Saves.Save.create!(%{
          sprite_id: sprite.id,
          mission_id: mission.id,
          wave_number: wave_number,
          checkpoint_id: checkpoint_id,
          comment: comment
        })

        Logger.info("Created checkpoint #{checkpoint_id} after wave #{wave_number}")

      {:error, reason} ->
        Logger.warning("Failed to create checkpoint: #{inspect(reason)}")
    end
  end

  defp truncate_output(output) when byte_size(output) > 100_000 do
    String.slice(output, -100_000, 100_000)
  end

  defp truncate_output(output), do: output

  @doc """
  Enqueues a mission to start running.
  """
  def enqueue(mission_id) do
    %{mission_id: mission_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
