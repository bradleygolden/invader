defmodule Invader.Campaigns.Executors.MissionExecutor do
  @moduledoc """
  Executes mission-type workflow nodes.

  Creates a real Mission record and waits for it to complete.
  """

  alias Invader.Missions.Mission
  alias Invader.Sprites.Sprite

  require Logger

  @doc """
  Execute a mission node.

  Config should contain:
  - sprite_id: The sprite to run the mission on
  - prompt: The mission prompt
  - max_waves: Maximum number of waves (optional, default 20)

  Returns {:ok, result} or {:error, reason}
  """
  def execute(config, context) do
    sprite_id = config["sprite_id"]
    prompt = interpolate_prompt(config["prompt"] || "", context)
    max_waves = config["max_waves"] || 20

    if is_nil(sprite_id) or sprite_id == "" do
      {:error, :missing_sprite_id}
    else
      case Sprite.get(sprite_id) do
        {:ok, sprite} ->
          create_and_run_mission(sprite, prompt, max_waves, context)

        {:error, _} ->
          {:error, :sprite_not_found}
      end
    end
  end

  defp create_and_run_mission(sprite, prompt, max_waves, _context) do
    case Mission.create(%{
           sprite_id: sprite.id,
           prompt: prompt,
           max_waves: max_waves
         }) do
      {:ok, mission} ->
        # Start the mission
        case Mission.start(mission) do
          {:ok, started_mission} ->
            # Enqueue the loop runner
            Invader.Workers.LoopRunner.enqueue(started_mission.id)

            # Wait for mission completion
            wait_for_mission_completion(started_mission.id)

          {:error, error} ->
            {:error, {:mission_start_failed, error}}
        end

      {:error, error} ->
        {:error, {:mission_create_failed, error}}
    end
  end

  defp wait_for_mission_completion(mission_id, timeout_ms \\ 3_600_000) do
    # Poll for mission completion
    # In a production system, you might want to use PubSub instead
    start_time = System.monotonic_time(:millisecond)
    poll_interval = 5_000

    do_wait(mission_id, start_time, timeout_ms, poll_interval)
  end

  defp do_wait(mission_id, start_time, timeout_ms, poll_interval) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed > timeout_ms do
      {:error, :mission_timeout}
    else
      case Mission.get(mission_id) do
        {:ok, mission} ->
          case mission.status do
            :completed ->
              {:ok, %{mission_id: mission_id, status: :completed}}

            :failed ->
              {:error, {:mission_failed, mission.error_message}}

            :aborted ->
              {:error, :mission_aborted}

            _ ->
              # Still running, wait and poll again
              Process.sleep(poll_interval)
              do_wait(mission_id, start_time, timeout_ms, poll_interval)
          end

        {:error, _} ->
          {:error, :mission_not_found}
      end
    end
  end

  defp interpolate_prompt(prompt, context) do
    # Simple variable interpolation: replace {{key}} with context value
    Regex.replace(~r/\{\{(\w+)\}\}/, prompt, fn _, key ->
      case Map.get(context, key) do
        nil -> "{{#{key}}}"
        value when is_binary(value) -> value
        value -> inspect(value)
      end
    end)
  end
end
