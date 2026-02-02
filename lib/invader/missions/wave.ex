defmodule Invader.Missions.Wave do
  @moduledoc """
  A wave represents a single iteration of a mission's autonomous loop.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Missions,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "waves"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :record, action: :record
    define :finish, action: :finish
    define :find_running, action: :find_running, args: [:mission_id, :number]
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:mission_id, :number]
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :finish do
      accept [:output, :exit_code]
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    read :find_running do
      argument :mission_id, :uuid, allow_nil?: false
      argument :number, :integer, allow_nil?: false

      filter expr(mission_id == ^arg(:mission_id) and number == ^arg(:number) and is_nil(finished_at))

      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      allow_nil? false
      public? true
    end

    attribute :started_at, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :finished_at, :utc_datetime do
      allow_nil? true
      public? true
    end

    attribute :output, :string do
      allow_nil? true
      public? true
      description "Captured stdout from the wave"
    end

    attribute :exit_code, :integer do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :mission, Invader.Missions.Mission do
      allow_nil? false
    end
  end
end
