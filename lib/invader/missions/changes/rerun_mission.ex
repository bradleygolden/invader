defmodule Invader.Missions.Changes.RerunMission do
  @moduledoc """
  Handles the conditional state transition for rerunning a mission.

  If the mission has a sprite_id, transitions to :pending.
  If the mission auto-creates sprites but has no sprite_id, transitions to :provisioning
  and enqueues the sprite provisioner.

  Note: Wave deletion is handled by the separate DeleteWaves change.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    sprite_id = changeset.data.sprite_id
    sprite_auto_created = changeset.data.sprite_auto_created

    if is_nil(sprite_id) and sprite_auto_created do
      changeset
      |> Ash.Changeset.change_attribute(:status, :provisioning)
      |> AshStateMachine.transition_state(:provisioning)
      |> Ash.Changeset.after_action(fn _changeset, mission ->
        Logger.info("Rerunning mission #{mission.id} - re-provisioning sprite")
        Invader.Workers.SpriteProvisioner.enqueue(mission.id)
        {:ok, mission}
      end)
    else
      changeset
      |> Ash.Changeset.change_attribute(:status, :pending)
      |> AshStateMachine.transition_state(:pending)
      |> Ash.Changeset.after_action(fn _changeset, mission ->
        Logger.info("Rerunning mission #{mission.id} - transitioning to pending")
        {:ok, mission}
      end)
    end
  end
end
