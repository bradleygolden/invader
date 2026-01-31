defmodule Invader.Repo.Migrations.AddMissionScheduling do
  @moduledoc """
  Add scheduling fields to missions table.
  """

  use Ecto.Migration

  def up do
    alter table(:missions) do
      add :schedule_enabled, :boolean, default: false
      add :schedule_type, :string
      add :schedule_cron, :text
      add :schedule_hour, :integer
      add :schedule_minute, :integer
      add :schedule_days, :text
      add :next_run_at, :utc_datetime
      add :last_scheduled_run_at, :utc_datetime
    end

    create index(:missions, [:schedule_enabled, :next_run_at])
  end

  def down do
    drop index(:missions, [:schedule_enabled, :next_run_at])

    alter table(:missions) do
      remove :schedule_enabled
      remove :schedule_type
      remove :schedule_cron
      remove :schedule_hour
      remove :schedule_minute
      remove :schedule_days
      remove :next_run_at
      remove :last_scheduled_run_at
    end
  end
end
