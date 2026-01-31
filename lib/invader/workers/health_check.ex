defmodule Invader.Workers.HealthCheck do
  @moduledoc """
  Periodic health check for running missions.

  Detects stalled missions (no output for N minutes) and triggers auto-recovery.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  alias Invader.Missions
  alias Invader.SpriteCli.Cli

  # Consider mission stalled if no wave completed in 30 minutes
  @stall_threshold_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    running_missions = get_running_missions()

    Enum.each(running_missions, fn mission ->
      check_mission_health(mission)
    end)

    :ok
  end

  defp get_running_missions do
    Missions.Mission
    |> Ash.Query.new()
    |> Ash.Query.filter_input(status: :running)
    |> Ash.Query.load([:sprite, :waves])
    |> Ash.read!()
  end

  defp check_mission_health(mission) do
    last_activity = get_last_activity(mission)
    stall_threshold = DateTime.add(DateTime.utc_now(), -@stall_threshold_minutes, :minute)

    if DateTime.compare(last_activity, stall_threshold) == :lt do
      handle_stalled_mission(mission)
    else
      # Check sprite is still responsive
      check_sprite_health(mission)
    end
  end

  defp get_last_activity(mission) do
    case mission.waves do
      [] ->
        mission.started_at || mission.inserted_at

      waves ->
        waves
        |> Enum.max_by(& &1.inserted_at, DateTime)
        |> Map.get(:finished_at)
        |> Kernel.||(mission.started_at)
    end
  end

  defp handle_stalled_mission(mission) do
    Logger.warning("Mission #{mission.id} appears stalled, attempting recovery")

    # Try to restore from last checkpoint
    case get_last_save(mission.id) do
      nil ->
        Logger.error("No checkpoint found for stalled mission #{mission.id}")
        Missions.Mission.fail(mission, %{error_message: "Stalled with no checkpoint"})

      save ->
        attempt_recovery(mission, save)
    end
  end

  defp get_last_save(mission_id) do
    Invader.Saves.Save
    |> Ash.Query.new()
    |> Ash.Query.filter_input(mission_id: mission_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end

  defp attempt_recovery(mission, save) do
    sprite = mission.sprite

    case Cli.restore(sprite.name, save.checkpoint_id) do
      {:ok, _} ->
        Logger.info("Restored mission #{mission.id} to checkpoint #{save.checkpoint_id}")

        # Update mission wave count and re-enqueue
        mission
        |> Ash.Changeset.for_update(:update, %{})
        |> Ash.Changeset.change_attribute(:current_wave, save.wave_number)
        |> Ash.update!()

        Invader.Workers.LoopRunner.enqueue(mission.id)

      {:error, reason} ->
        Logger.error("Failed to restore checkpoint: #{inspect(reason)}")
        Missions.Mission.fail(mission, %{error_message: "Recovery failed: #{inspect(reason)}"})
    end
  end

  defp check_sprite_health(mission) do
    case Cli.health_check(mission.sprite.name) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Sprite #{mission.sprite.name} health check failed: #{inspect(reason)}")
        # Don't fail immediately, but log for monitoring
    end
  end
end
