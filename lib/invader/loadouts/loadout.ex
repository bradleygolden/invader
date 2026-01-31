defmodule Invader.Loadouts.Loadout do
  @moduledoc """
  A loadout represents a reusable prompt configuration that can be quickly loaded into missions.
  """
  use Ash.Resource,
    otp_app: :invader,
    domain: Invader.Loadouts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "loadouts"
    repo Invader.Repo
  end

  code_interface do
    define :list, action: :read
    define :get, action: :read, get_by: [:id]
    define :get_by_name, action: :by_name, args: [:name]
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :content, :file_path, :description]
    end

    update :update do
      accept [:name, :content, :file_path, :description]
      require_atomic? false
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      filter expr(name == ^arg(:name))
      get? true
    end
  end

  validations do
    validate fn changeset, _context ->
      content = Ash.Changeset.get_attribute(changeset, :content)
      file_path = Ash.Changeset.get_attribute(changeset, :file_path)

      cond do
        content && content != "" && (file_path && file_path != "") ->
          {:error, field: :content, message: "cannot set both content and file_path"}

        (content && content != "") || (file_path && file_path != "") ->
          :ok

        true ->
          {:error, field: :content, message: "either content or file_path must be provided"}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      description "Unique name for the loadout"
    end

    attribute :content, :string do
      allow_nil? true
      public? true
      description "Inline prompt content"
    end

    attribute :file_path, :string do
      allow_nil? true
      public? true
      description "Path to prompt file"
    end

    attribute :description, :string do
      allow_nil? true
      public? true
      description "Optional description of what this loadout does"
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
