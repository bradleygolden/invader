defmodule Invader.Credentials.SavedCredential do
  @moduledoc """
  Stores API credentials securely for reuse across missions.
  Credentials are encrypted at rest using AshCloak.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Credentials,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshCloak]

  sqlite do
    table "saved_credentials"
    repo Invader.Repo
  end

  cloak do
    vault(Invader.Vault)
    attributes([:api_key])
    decrypt_by_default([:api_key])
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :get_by_provider, action: :by_provider, args: [:provider]
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:provider, :name, :api_key, :base_url]
    end

    update :update do
      accept [:name, :api_key, :base_url]
      require_atomic? false
    end

    read :by_provider do
      argument :provider, :atom, allow_nil?: false
      filter expr(provider == ^arg(:provider))
      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:anthropic_api, :zai, :custom]
      description "The API provider this credential is for"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      description "User-friendly name for this credential"
    end

    attribute :api_key, :string do
      allow_nil? false
      sensitive? true
      description "The encrypted API key"
    end

    attribute :base_url, :string do
      allow_nil? true
      public? true
      description "Custom base URL (for custom providers)"
    end

    timestamps()
  end

  identities do
    identity :unique_provider, [:provider]
  end
end
