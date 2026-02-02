defmodule Invader.Workers.SpriteDestroyer do
  @moduledoc """
  Oban worker that destroys sprites based on mission lifecycle settings.

  This worker is triggered:
  - On successful mission completion (when lifecycle is :destroy_on_complete)
  - When a mission is deleted (when lifecycle is :destroy_on_delete)

  Only auto-created sprites are destroyed - manually assigned sprites are never
  automatically destroyed.
  """
  use Oban.Worker,
    queue: :sprites,
    max_attempts: 3

  require Logger

  alias Invader.Sprites.Sprite
  alias Invader.SpriteCli.Cli

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sprite_id" => sprite_id, "sprite_name" => sprite_name}}) do
    Logger.info("Starting sprite destruction for #{sprite_name} (#{sprite_id})")

    with {:ok, _} <- destroy_remote_sprite(sprite_name),
         {:ok, _} <- delete_local_sprite(sprite_id) do
      Logger.info("Sprite #{sprite_name} destroyed successfully")
      :ok
    else
      {:error, :sprite_not_found} ->
        Logger.warning("Sprite #{sprite_name} not found, may have been manually deleted")
        # Still try to delete local record
        delete_local_sprite(sprite_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to destroy sprite #{sprite_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp destroy_remote_sprite(sprite_name) do
    Logger.info("Destroying sprite on sprites.dev: #{sprite_name}")

    case Cli.destroy(sprite_name) do
      :ok ->
        {:ok, :destroyed}

      {:error, %{status: 404}} ->
        {:error, :sprite_not_found}

      {:error, reason} ->
        {:error, {:remote_destroy_failed, reason}}
    end
  end

  defp delete_local_sprite(sprite_id) do
    Logger.info("Deleting local sprite record: #{sprite_id}")

    case Sprite.get(sprite_id) do
      {:ok, sprite} ->
        Ash.destroy!(sprite)
        {:ok, :deleted}

      {:error, %Ash.Error.Query.NotFound{}} ->
        Logger.warning("Local sprite record not found: #{sprite_id}")
        {:ok, :not_found}

      error ->
        error
    end
  end

  @doc """
  Enqueues a sprite for destruction.

  ## Parameters

    * `sprite_id` - The local sprite record ID
    * `sprite_name` - The sprite name on sprites.dev

  ## Options

    * `:schedule_in` - Delay before destruction in seconds (optional)
  """
  def enqueue(sprite_id, sprite_name, opts \\ []) do
    job_opts =
      case Keyword.get(opts, :schedule_in) do
        nil -> []
        seconds -> [schedule_in: seconds]
      end

    %{sprite_id: sprite_id, sprite_name: sprite_name}
    |> __MODULE__.new(job_opts)
    |> Oban.insert()
  end

  @doc """
  Checks if a mission's sprite should be destroyed based on its lifecycle setting.

  Returns true only if:
  - The sprite was auto-created by the mission
  - The lifecycle setting matches the trigger event
  """
  def should_destroy?(mission, trigger) do
    mission.sprite_auto_created &&
      case {mission.sprite_lifecycle, trigger} do
        {:destroy_on_complete, :completed} -> true
        {:destroy_on_delete, :deleted} -> true
        _ -> false
      end
  end
end
