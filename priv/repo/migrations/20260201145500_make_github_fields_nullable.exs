defmodule Invader.Repo.Migrations.MakeGithubFieldsNullable do
  @moduledoc """
  Makes github_id and github_login nullable to support magic link authentication.
  SQLite requires table recreation to change column constraints.
  """

  use Ecto.Migration

  def up do
    # SQLite doesn't support ALTER COLUMN, so we need to recreate the table
    # First, create a new table with the correct schema
    execute """
    CREATE TABLE users_new (
      id TEXT NOT NULL PRIMARY KEY,
      github_id INTEGER,
      github_login TEXT,
      email TEXT,
      name TEXT,
      avatar_url TEXT,
      is_admin INTEGER NOT NULL DEFAULT 0,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    # Copy data from old table
    execute """
    INSERT INTO users_new (id, github_id, github_login, email, name, avatar_url, is_admin, inserted_at, updated_at)
    SELECT id, github_id, github_login, email, name, avatar_url, is_admin, inserted_at, updated_at
    FROM users
    """

    # Drop old indexes
    execute "DROP INDEX IF EXISTS users_unique_github_id_index"
    execute "DROP INDEX IF EXISTS users_unique_email_index"

    # Drop old table
    execute "DROP TABLE users"

    # Rename new table
    execute "ALTER TABLE users_new RENAME TO users"

    # Recreate indexes
    create unique_index(:users, [:github_id],
             name: "users_unique_github_id_index",
             where: "github_id IS NOT NULL"
           )

    create unique_index(:users, [:email],
             name: "users_unique_email_index",
             where: "email IS NOT NULL"
           )
  end

  def down do
    # This is destructive - it will fail if there are users without github_id/github_login
    execute """
    CREATE TABLE users_new (
      id TEXT NOT NULL PRIMARY KEY,
      github_id INTEGER NOT NULL,
      github_login TEXT NOT NULL,
      email TEXT,
      name TEXT,
      avatar_url TEXT,
      is_admin INTEGER NOT NULL DEFAULT 0,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO users_new (id, github_id, github_login, email, name, avatar_url, is_admin, inserted_at, updated_at)
    SELECT id, github_id, github_login, email, name, avatar_url, is_admin, inserted_at, updated_at
    FROM users
    WHERE github_id IS NOT NULL AND github_login IS NOT NULL
    """

    execute "DROP INDEX IF EXISTS users_unique_github_id_index"
    execute "DROP INDEX IF EXISTS users_unique_email_index"

    execute "DROP TABLE users"

    execute "ALTER TABLE users_new RENAME TO users"

    create unique_index(:users, [:github_id], name: "users_unique_github_id_index")
    create unique_index(:users, [:email], name: "users_unique_email_index")
  end
end
