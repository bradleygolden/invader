defmodule Invader.Repo.Migrations.AllowHangingEdges do
  @moduledoc """
  Recreates workflow_edges table to allow hanging edges (nullify node references on delete).
  SQLite doesn't support ALTER for foreign key constraints, so we must recreate the table.
  """

  use Ecto.Migration

  def up do
    # Create temp table with new constraints
    execute """
    CREATE TABLE workflow_edges_new (
      id TEXT NOT NULL PRIMARY KEY,
      label TEXT,
      condition TEXT,
      is_loop_back INTEGER NOT NULL DEFAULT 0,
      max_iterations INTEGER,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      workflow_id TEXT NOT NULL REFERENCES workflows(id),
      source_node_id TEXT REFERENCES workflow_nodes(id) ON DELETE SET NULL,
      target_node_id TEXT REFERENCES workflow_nodes(id) ON DELETE SET NULL
    )
    """

    # Copy data
    execute """
    INSERT INTO workflow_edges_new
    SELECT id, label, condition, is_loop_back, max_iterations, inserted_at, updated_at,
           workflow_id, source_node_id, target_node_id
    FROM workflow_edges
    """

    # Drop old table and rename new
    execute "DROP TABLE workflow_edges"
    execute "ALTER TABLE workflow_edges_new RENAME TO workflow_edges"
  end

  def down do
    # Recreate with original constraints (no ON DELETE behavior)
    execute """
    CREATE TABLE workflow_edges_new (
      id TEXT NOT NULL PRIMARY KEY,
      label TEXT,
      condition TEXT,
      is_loop_back INTEGER NOT NULL DEFAULT 0,
      max_iterations INTEGER,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      workflow_id TEXT NOT NULL REFERENCES workflows(id),
      source_node_id TEXT NOT NULL REFERENCES workflow_nodes(id),
      target_node_id TEXT NOT NULL REFERENCES workflow_nodes(id)
    )
    """

    # Copy data (filter out any null references)
    execute """
    INSERT INTO workflow_edges_new
    SELECT id, label, condition, is_loop_back, max_iterations, inserted_at, updated_at,
           workflow_id, source_node_id, target_node_id
    FROM workflow_edges
    WHERE source_node_id IS NOT NULL AND target_node_id IS NOT NULL
    """

    execute "DROP TABLE workflow_edges"
    execute "ALTER TABLE workflow_edges_new RENAME TO workflow_edges"
  end
end
