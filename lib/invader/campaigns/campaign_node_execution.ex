defmodule Invader.Campaigns.CampaignNodeExecution do
  @moduledoc """
  Tracks individual node execution within a workflow run.
  Links to created Mission for mission nodes.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Campaigns,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "workflow_node_executions"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :update, action: :update
    define :for_run, action: :for_run, args: [:run_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:run_id, :node_id, :iteration]
    end

    update :update do
      accept [:status, :result, :error_message, :mission_id, :started_at, :finished_at]
    end

    update :start do
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      accept [:result]
      change set_attribute(:status, :completed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :fail do
      accept [:error_message]
      change set_attribute(:status, :failed)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :skip do
      change set_attribute(:status, :skipped)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    read :for_run do
      argument :run_id, :uuid, allow_nil?: false
      filter expr(run_id == ^arg(:run_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :running, :completed, :failed, :skipped]
    end

    attribute :iteration, :integer do
      allow_nil? false
      default 1
      public? true
      description "Which iteration of this node (for loops)"
    end

    attribute :result, :map do
      allow_nil? true
      public? true
      description "Output from the node execution"
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
    belongs_to :run, Invader.Campaigns.CampaignRun do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :node, Invader.Campaigns.CampaignNode do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :mission, Invader.Missions.Mission do
      allow_nil? true
      attribute_writable? true
      description "The mission created for mission-type nodes"
    end
  end
end
