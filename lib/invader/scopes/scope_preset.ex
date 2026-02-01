defmodule Invader.Scopes.ScopePreset do
  @moduledoc """
  A scope preset represents a reusable named collection of scopes.

  Examples:
  - "github-read-only" with scopes ["github:pr:list", "github:pr:view", "github:issue:list", "github:issue:view"]
  - "full-access" with scopes ["*"]
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Scopes,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "scope_presets"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :get_by_name, action: :by_name, args: [:name]
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :scopes, :is_system]
    end

    update :update do
      accept [:name, :description, :scopes]
      require_atomic? false

      # Prevent editing system presets
      validate attribute_equals(:is_system, false) do
        message "cannot modify system presets"
      end
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      filter expr(name == ^arg(:name))
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Unique name for the preset (e.g., 'github-read-only')"
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Description of what this preset allows"
    end

    attribute :scopes, {:array, :string} do
      allow_nil? false
      default []
      public? true
      description "Array of scope strings (e.g., ['github:pr:*', 'github:issue:view'])"
    end

    attribute :is_system, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether this is a built-in system preset (cannot be modified)"
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
