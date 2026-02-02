defmodule Invader.Missions.GithubRepo do
  @moduledoc """
  A GitHub repository associated with a mission.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Missions,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "mission_github_repos"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:mission_id, :owner, :name, :branch, :path]
    end

    update :update do
      accept [:branch, :path]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :owner, :string do
      allow_nil? false
      public? true
      description "GitHub owner (user or organization)"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Repository name"
    end

    attribute :branch, :string do
      allow_nil? true
      public? true
      default "main"
      description "Branch to use (defaults to main)"
    end

    attribute :path, :string do
      allow_nil? true
      public? true
      description "Subdirectory path within the repo"
    end

    timestamps()
  end

  relationships do
    belongs_to :mission, Invader.Missions.Mission do
      allow_nil? false
    end
  end
end
