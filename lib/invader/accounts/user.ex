defmodule Invader.Accounts.User do
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Accounts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAuthentication, AshAdmin.Resource],
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "users"
    repo Invader.Repo
  end

  authentication do
    tokens do
      enabled? true
      token_resource Invader.Accounts.Token
      require_token_presence_for_authentication? true
      store_all_tokens? true

      signing_secret fn _, _ ->
        Application.fetch_env(:invader, :token_signing_secret)
      end
    end

    strategies do
      github do
        client_id Invader.Secrets
        client_secret Invader.Secrets
        redirect_uri Invader.Secrets
        # Use sign-in mode since users must be pre-authorized
        registration_enabled? false
      end

      magic_link do
        identity_field :email
        single_use_token? true
        require_interaction? true

        sender fn user_or_email, token, _opts ->
          Invader.Accounts.Emails.send_magic_link(user_or_email, token)
        end
      end
    end
  end

  admin do
    actor? true
  end

  code_interface do
    define :get_by_github_id, action: :read, get_by: [:github_id]
    define :get_by_github_login, action: :read, get_by: [:github_login]
    define :get_by_email, action: :read, get_by: [:email]
    define :count_users, action: :count_all
  end

  actions do
    defaults [:read]

    read :count_all do
      prepare build(select: [:id])
    end

    # Sign-in action for GitHub OAuth (used with registration_enabled? false)
    # Note: user_info uses OpenID Connect fields: "sub" (id), "preferred_username" (login), "picture" (avatar)
    read :sign_in_with_github do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false

      prepare AshAuthentication.Strategy.OAuth2.SignInPreparation
      prepare Invader.Accounts.User.Preparations.UpdateGitHubAttributes

      # Match by github_id (returning users) OR github_login (first-time pre-authorized users)
      filter expr(
               github_id == get_path(^arg(:user_info), ["sub"]) or
                 (is_nil(github_id) and
                    github_login == get_path(^arg(:user_info), ["preferred_username"]))
             )
    end

    create :create do
      description "Admin action to pre-authorize a GitHub user"
      accept [:github_id, :github_login, :email, :name, :is_admin]
    end

    update :update do
      description "Admin action to update a user"
      accept [:email, :name, :is_admin]
    end

    update :update_from_oauth do
      description "Update user with GitHub OAuth data on sign-in"
      accept [:github_id, :github_login, :email, :name, :avatar_url]
    end

    destroy :destroy do
      description "Admin action to remove a user"
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :github_id, :integer do
      allow_nil? true
      public? true
    end

    attribute :github_login, :string do
      allow_nil? true
      public? true
    end

    attribute :email, :string do
      allow_nil? true
      public? true
    end

    attribute :name, :string do
      allow_nil? true
      public? true
    end

    attribute :avatar_url, :string do
      allow_nil? true
      public? true
    end

    attribute :is_admin, :boolean do
      default false
      allow_nil? false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_github_id, [:github_id]
    identity :unique_email, [:email]
  end
end
