defmodule Invader.Missions.Changes.DeleteWaves do
  @moduledoc """
  Deletes all wave records for a mission when rerunning or retrying.
  This ensures the mission starts fresh without duplicate wave numbers.
  """
  use Ash.Resource.Change

  require Logger

  alias Invader.Missions.Wave

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, mission ->
      delete_waves_for_mission(mission.id)
      {:ok, mission}
    end)
  end

  defp delete_waves_for_mission(mission_id) do
    case Wave.list() do
      {:ok, waves} ->
        waves
        |> Enum.filter(&(&1.mission_id == mission_id))
        |> Enum.each(fn wave ->
          Logger.info("Deleting wave #{wave.id} (wave ##{wave.number}) for mission rerun")
          Ash.destroy!(wave)
        end)

      _ ->
        :ok
    end
  end
end
