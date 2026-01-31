defmodule Invader.Workers.FleetStatusSync do
  @moduledoc """
  Periodic sync of fleet status from the Sprites API.

  Runs on a cron schedule to ensure sprite statuses are up to date.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  alias Invader.Sprites.Sprite

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting fleet status sync")

    case Sprite.sync() do
      {:ok, sprites} ->
        Logger.info("Fleet status sync completed: #{length(sprites)} sprites synced")

        Phoenix.PubSub.broadcast(
          Invader.PubSub,
          "sprites:updates",
          {:sprites_synced, sprites}
        )

        :ok

      {:error, reason} ->
        Logger.error("Fleet status sync failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
