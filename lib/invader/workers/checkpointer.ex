defmodule Invader.Workers.Checkpointer do
  @moduledoc """
  Creates periodic checkpoints and prunes old ones.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1

  require Logger

  alias Invader.Saves
  alias Invader.SpriteCli.Cli

  # Keep last N checkpoints per mission
  @max_checkpoints_per_mission 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{"action" => "create", "sprite_id" => sprite_id, "comment" => comment} ->
        create_checkpoint(sprite_id, comment)

      %{"action" => "prune"} ->
        prune_old_checkpoints()

      _ ->
        Logger.warning("Unknown checkpointer action: #{inspect(args)}")
        :ok
    end
  end

  defp create_checkpoint(sprite_id, comment) do
    {:ok, sprite} = Invader.Sprites.Sprite.get(sprite_id)

    case Cli.checkpoint_create(sprite.name, comment) do
      {:ok, checkpoint_id} ->
        Saves.Save.create!(%{
          sprite_id: sprite_id,
          checkpoint_id: checkpoint_id,
          comment: comment
        })

        Logger.info("Created checkpoint #{checkpoint_id} for sprite #{sprite.name}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to create checkpoint: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp prune_old_checkpoints do
    # Get all completed/failed/aborted missions
    finished_statuses = [:completed, :failed, :aborted]

    mission_ids =
      Invader.Missions.Mission
      |> Ash.read!()
      |> Enum.filter(fn m -> m.status in finished_statuses end)
      |> Enum.map(& &1.id)

    Enum.each(mission_ids, fn mission_id ->
      prune_mission_checkpoints(mission_id)
    end)

    :ok
  end

  defp prune_mission_checkpoints(mission_id) do
    saves =
      Saves.Save
      |> Ash.Query.new()
      |> Ash.Query.filter_input(mission_id: mission_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()

    # Keep the most recent ones, delete the rest
    saves
    |> Enum.drop(@max_checkpoints_per_mission)
    |> Enum.each(fn save ->
      Logger.info("Pruning old checkpoint #{save.checkpoint_id}")
      Ash.destroy!(save)
    end)
  end

  @doc """
  Schedule a checkpoint creation.
  """
  def schedule_create(sprite_id, comment \\ nil) do
    %{action: "create", sprite_id: sprite_id, comment: comment || "manual"}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule checkpoint pruning.
  """
  def schedule_prune do
    %{action: "prune"}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
