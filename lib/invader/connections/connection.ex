defmodule Invader.Connections.Connection do
  @moduledoc """
  Represents an external service connection (GitHub, Linear, etc.).
  Stores credentials securely for proxy operations.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Connections,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshCloak]

  sqlite do
    table "connections"
    repo Invader.Repo
  end

  cloak do
    vault(Invader.Vault)
    attributes([:private_key])
    decrypt_by_default([:private_key])
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :get_by_type, action: :by_type, args: [:type]
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:type, :name, :app_id, :installation_id, :private_key]
      change set_attribute(:status, :pending)
    end

    update :update do
      accept [:name, :app_id, :installation_id, :private_key, :status]
      require_atomic? false
    end

    read :by_type do
      argument :type, :atom, allow_nil?: false
      filter expr(type == ^arg(:type))
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:github]
      description "Type of connection (github, linear, etc.)"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      description "User-friendly name for this connection"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :connected, :error]
      description "Connection status"
    end

    # GitHub App credentials
    attribute :app_id, :string do
      allow_nil? true
      public? true
      description "GitHub App ID"
    end

    attribute :installation_id, :string do
      allow_nil? true
      public? true
      description "GitHub App Installation ID"
    end

    attribute :private_key, :string do
      allow_nil? true
      sensitive? true
      description "GitHub App private key (PEM format)"
    end

    timestamps()
  end

  relationships do
    has_many :requests, Invader.Connections.Request
  end

  identities do
    identity :unique_type, [:type]
  end
end
