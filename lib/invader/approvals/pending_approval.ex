defmodule Invader.Approvals.PendingApproval do
  @moduledoc """
  Tracks approval requests waiting for human decision.

  When an agent attempts an action that requires approval,
  a PendingApproval record is created and the agent blocks
  until the human approves or denies via Telegram.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Approvals,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "pending_approvals"
    repo Invader.Repo
  end

  code_interface do
    define :create, action: :create
    define :get, action: :read, get_by: [:id]

    define :get_pending_by_callback_data,
      action: :pending_by_callback_data,
      args: [:callback_data]

    define :list_pending, action: :pending
    define :approve, action: :approve, args: [:decided_by]
    define :deny, action: :deny, args: [:decided_by]
    define :timeout, action: :timeout
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :mission_id,
        :scope,
        :action_type,
        :action_details,
        :caller_pid,
        :timeout_at,
        :callback_data
      ]

      change set_attribute(:status, :pending)
    end

    update :approve do
      accept []
      argument :decided_by, :string, allow_nil?: false
      require_atomic? false

      change set_attribute(:status, :approved)
      change set_attribute(:decided_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        decided_by = Ash.Changeset.get_argument(changeset, :decided_by)
        Ash.Changeset.change_attribute(changeset, :decided_by, decided_by)
      end
    end

    update :deny do
      accept []
      argument :decided_by, :string, allow_nil?: false
      require_atomic? false

      change set_attribute(:status, :denied)
      change set_attribute(:decided_at, &DateTime.utc_now/0)

      change fn changeset, _context ->
        decided_by = Ash.Changeset.get_argument(changeset, :decided_by)
        Ash.Changeset.change_attribute(changeset, :decided_by, decided_by)
      end
    end

    update :timeout do
      accept []
      require_atomic? false
      change set_attribute(:status, :timeout)
      change set_attribute(:decided_at, &DateTime.utc_now/0)
    end

    read :pending do
      filter expr(status == :pending)
    end

    read :pending_by_callback_data do
      argument :callback_data, :string, allow_nil?: false

      filter expr(callback_data == ^arg(:callback_data) and status == :pending)

      get? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mission_id, :uuid do
      allow_nil? false
      public? true
      description "The mission requesting approval"
    end

    attribute :scope, :string do
      allow_nil? false
      public? true
      description "The scope requiring approval (e.g., github:pr:create)"
    end

    attribute :action_type, :string do
      allow_nil? true
      public? true
      description "Type of action: gh, telegram, etc."
    end

    attribute :action_details, :map do
      allow_nil? true
      public? true
      description "Command args and other details"
    end

    attribute :caller_pid, :binary do
      allow_nil? true
      description "Erlang term-encoded PID of the waiting process"
    end

    attribute :callback_data, :string do
      allow_nil? false
      public? true
      description "Unique callback data for Telegram inline buttons"
    end

    attribute :timeout_at, :utc_datetime do
      allow_nil? false
      public? true
      description "When this approval request expires"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :approved, :denied, :timeout]
      description "Approval status"
    end

    attribute :decided_by, :string do
      allow_nil? true
      public? true
      description "Who made the decision (e.g., telegram:@username)"
    end

    attribute :decided_at, :utc_datetime do
      allow_nil? true
      public? true
      description "When the decision was made"
    end

    timestamps()
  end
end
