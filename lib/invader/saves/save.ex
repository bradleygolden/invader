defmodule Invader.Saves.Save do
  @moduledoc """
  A save represents a sprite checkpoint that can be restored.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Saves,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "saves"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :create, action: :create
    define :for_sprite, action: :for_sprite, args: [:sprite_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:sprite_id, :mission_id, :wave_number, :checkpoint_id, :comment]
    end

    read :for_sprite do
      argument :sprite_id, :uuid, allow_nil?: false
      filter expr(sprite_id == ^arg(:sprite_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :checkpoint_id, :string do
      allow_nil? false
      public? true
      description "Checkpoint ID from sprite CLI"
    end

    attribute :wave_number, :integer do
      allow_nil? true
      public? true
    end

    attribute :comment, :string do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :sprite, Invader.Sprites.Sprite do
      allow_nil? false
    end

    belongs_to :mission, Invader.Missions.Mission do
      allow_nil? true
    end
  end
end
