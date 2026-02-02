defmodule Invader.Campaigns.CampaignNode do
  @moduledoc """
  A node in a workflow graph. Types include:
  - mission: Creates and runs a mission
  - conditional: Evaluates a condition to determine branch
  - delay: Waits for a specified duration
  - loop: Manages iteration with counter and condition
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Campaigns,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "workflow_nodes"
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
        :node_type,
        :label,
        :config,
        :position_x,
        :position_y,
        :is_start
      ]
    end

    update :update do
      accept [
        :node_type,
        :label,
        :config,
        :position_x,
        :position_y,
        :is_start
      ]
    end

    read :for_workflow do
      argument :workflow_id, :uuid, allow_nil?: false
      filter expr(workflow_id == ^arg(:workflow_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :node_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:mission, :conditional, :delay, :loop]
    end

    attribute :label, :string do
      allow_nil? true
      public? true
      description "Display label for the node in the editor"
    end

    attribute :config, :map do
      allow_nil? true
      public? true

      description "Node-specific configuration (sprite_id, prompt, condition, delay_seconds, etc.)"
    end

    attribute :position_x, :float do
      allow_nil? false
      default 0.0
      public? true
    end

    attribute :position_y, :float do
      allow_nil? false
      default 0.0
      public? true
    end

    attribute :is_start, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether this node is the workflow entry point"
    end

    timestamps()
  end

  relationships do
    belongs_to :workflow, Invader.Campaigns.Campaign do
      allow_nil? false
    end

    has_many :outgoing_edges, Invader.Campaigns.CampaignEdge do
      destination_attribute :source_node_id
    end

    has_many :incoming_edges, Invader.Campaigns.CampaignEdge do
      destination_attribute :target_node_id
    end

    has_many :executions, Invader.Campaigns.CampaignNodeExecution do
      destination_attribute :node_id
    end
  end
end
