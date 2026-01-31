defmodule Invader.Missions.Changes.EnqueueLoopRunner do
  @moduledoc """
  Enqueues the LoopRunner worker to start executing mission waves.
  """
  use Ash.Resource.Change

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, mission ->
      Logger.info("Enqueuing scheduled mission #{mission.id} for execution")
      Invader.Workers.LoopRunner.enqueue(mission.id)
      {:ok, mission}
    end)
  end
end
