defmodule Invader.Missions.Changes.ScheduleNextRun do
  @moduledoc """
  Calculates and sets the next_run_at time for scheduled missions.
  """
  use Ash.Resource.Change

  alias Invader.Missions.ScheduleCalculator

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, mission ->
      case ScheduleCalculator.next_run_at(mission) do
        {:ok, next_run} ->
          mission
          |> Ash.Changeset.for_update(:update, %{})
          |> Ash.Changeset.force_change_attribute(:next_run_at, next_run)
          |> Ash.update()

        {:error, reason} ->
          require Logger
          Logger.warning("Failed to calculate next run time: #{inspect(reason)}")
          {:ok, mission}
      end
    end)
  end
end
