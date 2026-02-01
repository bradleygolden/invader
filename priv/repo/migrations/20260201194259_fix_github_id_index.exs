defmodule Invader.Repo.Migrations.FixGithubIdIndex do
  use Ecto.Migration

  def change do
    # Drop the partial index that SQLite can't use for ON CONFLICT
    drop_if_exists index(:users, [:github_id], name: "users_unique_github_id_index")

    # Create a regular unique index (SQLite allows multiple NULLs in unique indexes)
    create unique_index(:users, [:github_id], name: "users_github_id_unique_index")
  end
end
