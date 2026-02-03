defmodule Invader.Connections.Telegram.PendingPrompt do
  @moduledoc """
  Tracks prompts awaiting user replies in Telegram.

  When `ask/3` sends a message, a PendingPrompt is created to track:
  - The message ID for matching incoming replies
  - The caller PID to notify when a reply arrives
  - Timeout handling for stale prompts
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Connections,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "telegram_pending_prompts"
    repo Invader.Repo
  end

  code_interface do
    define :create, action: :create
    define :get, action: :read, get_by: [:id]
    define :get_by_message, action: :by_message, args: [:chat_id, :message_id]
    define :list_pending, action: :pending
    define :mark_responded, action: :mark_responded, args: [:response_text]
    define :mark_timeout, action: :mark_timeout
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:chat_id, :message_id, :caller_pid, :timeout_at, :mission_id]
      change set_attribute(:status, :pending)
    end

    update :mark_responded do
      accept []
      argument :response_text, :string, allow_nil?: false
      require_atomic? false

      change set_attribute(:status, :responded)

      change fn changeset, _context ->
        response = Ash.Changeset.get_argument(changeset, :response_text)
        Ash.Changeset.change_attribute(changeset, :response_text, response)
      end
    end

    update :mark_timeout do
      accept []
      require_atomic? false
      change set_attribute(:status, :timeout)
    end

    read :by_message do
      argument :chat_id, :integer, allow_nil?: false
      argument :message_id, :integer, allow_nil?: false

      filter expr(
               chat_id == ^arg(:chat_id) and message_id == ^arg(:message_id) and
                 status == :pending
             )

      get? true
    end

    read :pending do
      filter expr(status == :pending)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :chat_id, :integer do
      allow_nil? false
      public? true
      description "Telegram chat ID"
    end

    attribute :message_id, :integer do
      allow_nil? false
      public? true
      description "Telegram message ID of the prompt"
    end

    attribute :caller_pid, :binary do
      allow_nil? true
      description "Erlang term-encoded PID of the waiting process"
    end

    attribute :timeout_at, :utc_datetime do
      allow_nil? false
      public? true
      description "When this prompt should be considered timed out"
    end

    attribute :mission_id, :uuid do
      allow_nil? true
      public? true
      description "Optional mission context"
    end

    attribute :response_text, :string do
      allow_nil? true
      public? true
      description "User's reply text"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :responded, :timeout]
      description "Prompt status"
    end

    timestamps()
  end
end
