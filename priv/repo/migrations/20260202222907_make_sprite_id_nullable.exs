defmodule Invader.Repo.Migrations.MakeSpriteIdNullable do
  @moduledoc """
  Makes sprite_id nullable to support create_with_sprite action.
  """

  use Ecto.Migration

  def up do
    # Disable foreign key checks temporarily
    execute "PRAGMA foreign_keys = OFF"

    # SQLite doesn't support ALTER COLUMN, so we need to recreate the table
    execute """
    CREATE TABLE missions_new (
      id TEXT PRIMARY KEY NOT NULL,
      prompt_path TEXT,
      prompt TEXT,
      priority INTEGER,
      max_waves INTEGER,
      max_duration INTEGER,
      current_wave INTEGER,
      status TEXT NOT NULL,
      state TEXT NOT NULL,
      error_message TEXT,
      started_at TEXT,
      finished_at TEXT,
      sprite_id TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      schedule_enabled INTEGER DEFAULT false,
      schedule_type TEXT,
      schedule_cron TEXT,
      schedule_hour INTEGER,
      schedule_minute INTEGER,
      schedule_days TEXT,
      next_run_at TEXT,
      last_scheduled_run_at TEXT,
      scopes TEXT,
      scope_preset_id TEXT,
      sprite_name TEXT,
      sprite_auto_created INTEGER,
      sprite_lifecycle TEXT,
      agent_type TEXT,
      agent_command TEXT,
      agent_provider TEXT,
      agent_base_url TEXT,
      agent_api_key TEXT,
      FOREIGN KEY (sprite_id) REFERENCES sprites(id),
      FOREIGN KEY (scope_preset_id) REFERENCES scope_presets(id)
    )
    """

    execute """
    INSERT INTO missions_new
    SELECT id, prompt_path, prompt, priority, max_waves, max_duration, current_wave,
           status, state, error_message, started_at, finished_at, sprite_id,
           inserted_at, updated_at, schedule_enabled, schedule_type, schedule_cron,
           schedule_hour, schedule_minute, schedule_days, next_run_at,
           last_scheduled_run_at, scopes, scope_preset_id, sprite_name,
           sprite_auto_created, sprite_lifecycle, agent_type, agent_command,
           agent_provider, agent_base_url, agent_api_key
    FROM missions
    """

    execute "DROP TABLE missions"
    execute "ALTER TABLE missions_new RENAME TO missions"

    # Recreate indexes
    execute "CREATE INDEX missions_sprite_id_index ON missions(sprite_id)"
    execute "CREATE INDEX missions_scope_preset_id_index ON missions(scope_preset_id)"

    # Re-enable foreign key checks
    execute "PRAGMA foreign_keys = ON"
  end

  def down do
    :ok
  end
end
