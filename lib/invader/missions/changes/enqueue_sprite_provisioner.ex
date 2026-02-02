defmodule Invader.Missions.Changes.EnqueueSpriteProvisioner do
  @moduledoc """
  Enqueues the SpriteProvisioner worker to create a sprite for the mission.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, mission ->
      Logger.info("Enqueuing sprite provisioning for mission #{mission.id}")
      Invader.Workers.SpriteProvisioner.enqueue(mission.id)
      {:ok, mission}
    end)
  end
end
