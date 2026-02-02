defmodule Invader.Campaigns.Campaign do
  @moduledoc """
  A workflow is a top-level container for orchestrating multiple missions as a directed graph.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Campaigns,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "workflows"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :layout_data]
    end

    update :update do
      accept [:name, :description, :status, :layout_data]
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          campaign = Ash.load!(changeset.data, [:nodes, :edges, :runs])

          # Delete related records first (order matters for foreign keys)
          Enum.each(campaign.runs, &Ash.destroy!/1)
          Enum.each(campaign.edges, &Ash.destroy!/1)
          Enum.each(campaign.nodes, &Ash.destroy!/1)

          changeset
        end)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :draft
      public? true
      constraints one_of: [:draft, :active, :archived]
    end

    attribute :layout_data, :map do
      allow_nil? true
      public? true
      description "Stores visual positions of nodes for the editor"
    end

    timestamps()
  end

  relationships do
    has_many :nodes, Invader.Campaigns.CampaignNode do
      destination_attribute :workflow_id
    end

    has_many :edges, Invader.Campaigns.CampaignEdge do
      destination_attribute :workflow_id
    end

    has_many :runs, Invader.Campaigns.CampaignRun do
      destination_attribute :workflow_id
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
