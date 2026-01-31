defmodule Invader.Repo.Migrations.AddLoadouts do
  @moduledoc """
  Creates the loadouts table for reusable prompt configurations.
  """

  use Ecto.Migration

  def up do
    create table(:loadouts, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :content, :text
      add :file_path, :text
      add :description, :text
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:loadouts, [:name], name: "loadouts_unique_name_index")
  end

  def down do
    drop_if_exists unique_index(:loadouts, [:name], name: "loadouts_unique_name_index")
    drop table(:loadouts)
  end
end
