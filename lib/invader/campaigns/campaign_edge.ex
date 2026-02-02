defmodule Invader.Campaigns.CampaignEdge do
  @moduledoc """
  An edge connecting two nodes in a workflow graph.
  Supports loop-back edges with iteration limits and conditions.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Campaigns,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "workflow_edges"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
    define :for_workflow, action: :for_workflow, args: [:workflow_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :workflow_id,
        :source_node_id,
        :target_node_id,
        :label,
        :condition,
        :is_loop_back,
        :max_iterations
      ]
    end

    update :update do
      accept [
        :label,
        :condition,
        :is_loop_back,
        :max_iterations
      ]
    end

    read :for_workflow do
      argument :workflow_id, :uuid, allow_nil?: false
      filter expr(workflow_id == ^arg(:workflow_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :label, :string do
      allow_nil? true
      public? true
      description "Optional label for the edge (e.g., 'yes', 'no' for conditionals)"
    end

    attribute :condition, :string do
      allow_nil? true
      public? true
      description "Expression to evaluate for conditional routing"
    end

    attribute :is_loop_back, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether this edge cycles back to an earlier node"
    end

    attribute :max_iterations, :integer do
      allow_nil? true
      public? true
      description "Maximum iterations for loop-back edges"
    end

    timestamps()
  end

  relationships do
    belongs_to :workflow, Invader.Campaigns.Campaign do
      allow_nil? false
    end

    belongs_to :source_node, Invader.Campaigns.CampaignNode do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :target_node, Invader.Campaigns.CampaignNode do
      allow_nil? true
      attribute_writable? true
    end
  end
end
