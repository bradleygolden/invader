defmodule Invader.Connections.Request do
  @moduledoc """
  Audit trail for proxy requests made through connections.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Connections,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "connection_requests"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :list_by_connection, action: :by_connection, args: [:connection_id]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:connection_id, :sprite_id, :command, :mode, :status, :result, :duration_ms]
    end

    read :by_connection do
      argument :connection_id, :uuid, allow_nil?: false
      filter expr(connection_id == ^arg(:connection_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sprite_id, :string do
      allow_nil? true
      public? true
      description "ID of the sprite that made the request"
    end

    attribute :command, :string do
      allow_nil? false
      public? true
      description "The command that was executed (e.g., 'pr list --repo foo/bar')"
    end

    attribute :mode, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:proxy, :token]
      description "Execution mode: proxy (server) or token (local)"
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:pending, :completed, :failed]
      description "Request status"
    end

    attribute :result, :map do
      allow_nil? true
      public? true
      description "Result of the request (output, error, etc.)"
    end

    attribute :duration_ms, :integer do
      allow_nil? true
      public? true
      description "How long the request took in milliseconds"
    end

    timestamps()
  end

  relationships do
    belongs_to :connection, Invader.Connections.Connection do
      allow_nil? false
    end
  end
end
