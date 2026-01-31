defmodule Invader.Repo.Migrations.MakePromptPathNullable do
  @moduledoc """
  Makes prompt_path nullable so missions can use inline prompts instead.

  SQLite doesn't support ALTER COLUMN, so we recreate the table.
  """

  use Ecto.Migration

  def up do
    # SQLite doesn't support ALTER COLUMN, so we need to recreate the table
    execute """
    CREATE TABLE missions_new (
      id TEXT NOT NULL PRIMARY KEY,
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
      sprite_id TEXT NOT NULL REFERENCES sprites(id),
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO missions_new (
      id, prompt_path, prompt, priority, max_waves, max_duration, current_wave,
      status, state, error_message, started_at, finished_at, sprite_id,
      inserted_at, updated_at
    )
    SELECT
      id, prompt_path, prompt, priority, max_waves, max_duration, current_wave,
      status, state, error_message, started_at, finished_at, sprite_id,
      inserted_at, updated_at
    FROM missions
    """

    execute "DROP TABLE missions"
    execute "ALTER TABLE missions_new RENAME TO missions"
  end

  def down do
    # Reverse: make prompt_path NOT NULL again (will fail if any rows have NULL prompt_path)
    execute """
    CREATE TABLE missions_new (
      id TEXT NOT NULL PRIMARY KEY,
      prompt_path TEXT NOT NULL,
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
      sprite_id TEXT NOT NULL REFERENCES sprites(id),
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO missions_new (
      id, prompt_path, prompt, priority, max_waves, max_duration, current_wave,
      status, state, error_message, started_at, finished_at, sprite_id,
      inserted_at, updated_at
    )
    SELECT
      id, prompt_path, prompt, priority, max_waves, max_duration, current_wave,
      status, state, error_message, started_at, finished_at, sprite_id,
      inserted_at, updated_at
    FROM missions
    """

    execute "DROP TABLE missions"
    execute "ALTER TABLE missions_new RENAME TO missions"
  end
end
