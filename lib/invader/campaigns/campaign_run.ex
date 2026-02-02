defmodule Invader.Campaigns.CampaignRun do
  @moduledoc """
  An execution instance of a workflow with state machine for status tracking.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Campaigns,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  sqlite do
    table "workflow_runs"
    repo Invader.Repo
  end

  state_machine do
    initial_states [:pending]
    default_initial_state :pending

    transitions do
      transition :start, from: :pending, to: :running
      transition :pause, from: :running, to: :paused
      transition :resume, from: :paused, to: :running
      transition :complete, from: :running, to: :completed
      transition :fail, from: [:running, :paused], to: :failed
      transition :cancel, from: [:pending, :running, :paused], to: :cancelled
    end
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :start, action: :start
    define :pause, action: :pause
    define :resume, action: :resume
    define :complete, action: :complete
    define :fail, action: :fail
    define :cancel, action: :cancel
    define :for_workflow, action: :for_workflow, args: [:workflow_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:workflow_id]
    end

    update :start do
      change transition_state(:running)
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :pause do
      change transition_state(:paused)
      change set_attribute(:status, :paused)
    end

    update :resume do
      change transition_state(:running)
      change set_attribute(:status, :running)
    end

    update :complete do
      change transition_state(:completed)
      change set_attribute(:status, :completed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]
      change transition_state(:failed)
      change set_attribute(:status, :failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :cancel do
      change transition_state(:cancelled)
      change set_attribute(:status, :cancelled)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :update_context do
      accept [:context]
    end

    read :for_workflow do
      argument :workflow_id, :uuid, allow_nil?: false
      filter expr(workflow_id == ^arg(:workflow_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :paused, :completed, :failed, :cancelled]
    end

    attribute :context, :map do
      allow_nil? true
      public? true
      description "Runtime variables and iteration counters"
    end

    attribute :error_message, :string do
      allow_nil? true
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

    timestamps()
  end

  relationships do
    belongs_to :workflow, Invader.Campaigns.Campaign do
      allow_nil? false
    end

    has_many :node_executions, Invader.Campaigns.CampaignNodeExecution do
      destination_attribute :run_id
    end
  end
end
