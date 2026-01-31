defmodule Invader.Sprites.Sprite do
  @moduledoc """
  Represents a sprite.dev environment - a persistent Linux VM with checkpointing.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Sprites,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "sprites"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :get_by_name, action: :by_name, args: [:name]
    define :create, action: :create
    define :update, action: :update
    define :sync, action: :sync
    define :update_status, action: :update_status, args: [:status]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :org, :status]
    end

    update :update do
      accept [:name, :org, :status]
    end

    update :update_status do
      accept []
      argument :status, :atom, allow_nil?: false

      change set_attribute(:status, arg(:status))
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      filter expr(name == ^arg(:name))
      get? true
    end

    action :sync, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]
      run Invader.Sprites.Actions.SyncFromApi
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :org, :string do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      default :unknown
      public? true
      constraints one_of: [:available, :busy, :offline, :unknown]
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
