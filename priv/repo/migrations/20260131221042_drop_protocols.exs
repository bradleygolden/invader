defmodule Invader.Repo.Migrations.DropProtocols do
  use Ecto.Migration

  def change do
    drop table(:protocols)
  end
end
