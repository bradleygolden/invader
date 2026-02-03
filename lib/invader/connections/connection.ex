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
    attributes([:private_key, :token, :telegram_bot_token, :telegram_webhook_secret])
    decrypt_by_default([:private_key, :token, :telegram_bot_token, :telegram_webhook_secret])
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
      accept [
        :type,
        :name,
        :app_id,
        :installation_id,
        :private_key,
        :token,
        :telegram_bot_token,
        :telegram_chat_id,
        :telegram_username,
        :telegram_webhook_secret
      ]

      change set_attribute(:status, :pending)
    end

    update :update do
      accept [
        :name,
        :app_id,
        :installation_id,
        :private_key,
        :token,
        :status,
        :telegram_bot_token,
        :telegram_chat_id,
        :telegram_username,
        :telegram_webhook_secret
      ]

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
      constraints one_of: [:github, :sprites, :telegram]
      description "Type of connection (github, sprites, telegram, etc.)"
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

    attribute :token, :string do
      allow_nil? true
      sensitive? true
      description "API token (for Sprites and other token-based services)"
    end

    # Telegram Bot credentials
    attribute :telegram_bot_token, :string do
      allow_nil? true
      sensitive? true
      description "Telegram Bot API token from @BotFather"
    end

    attribute :telegram_chat_id, :integer do
      allow_nil? true
      public? true
      description "Telegram chat ID for sending notifications"
    end

    attribute :telegram_username, :string do
      allow_nil? true
      public? true
      description "Telegram username of the connected user"
    end

    attribute :telegram_webhook_secret, :string do
      allow_nil? true
      sensitive? true
      description "Secret token for verifying webhook requests"
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
