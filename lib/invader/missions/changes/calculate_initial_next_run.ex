defmodule Invader.Missions.Changes.CalculateInitialNextRun do
  @moduledoc """
  Calculates the initial next_run_at time when a scheduled mission is created or updated.
  Only calculates if schedule_enabled is true and next_run_at is not explicitly set.
  """
  use Ash.Resource.Change

  alias Invader.Missions.ScheduleCalculator

  @impl true
  def change(changeset, _opts, _context) do
    schedule_enabled = Ash.Changeset.get_attribute(changeset, :schedule_enabled)
    schedule_type = Ash.Changeset.get_attribute(changeset, :schedule_type)
    next_run_at = Ash.Changeset.get_attribute(changeset, :next_run_at)

    # Only calculate if scheduling is enabled and next_run_at not explicitly provided
    # For :once type, next_run_at must be set by user
    if schedule_enabled && schedule_type && schedule_type != :once && is_nil(next_run_at) do
      # Build a temporary struct to calculate next run
      mission_data = %{
        schedule_enabled: schedule_enabled,
        schedule_type: schedule_type,
        schedule_cron: Ash.Changeset.get_attribute(changeset, :schedule_cron),
        schedule_hour: Ash.Changeset.get_attribute(changeset, :schedule_hour),
        schedule_minute: Ash.Changeset.get_attribute(changeset, :schedule_minute),
        schedule_days: Ash.Changeset.get_attribute(changeset, :schedule_days)
      }

      case ScheduleCalculator.next_run_at(mission_data) do
        {:ok, calculated_next_run} when not is_nil(calculated_next_run) ->
          Ash.Changeset.force_change_attribute(changeset, :next_run_at, calculated_next_run)

        _ ->
          changeset
      end
    else
      changeset
    end
  end
end
