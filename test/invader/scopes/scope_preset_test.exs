defmodule Invader.Scopes.ScopePresetTest do
  use Invader.DataCase

  alias Invader.Scopes.ScopePreset
  alias Invader.Factory

  describe "create/1" do
    test "creates preset with valid attrs" do
      attrs = %{
        name: "test-preset",
        description: "Test description",
        scopes: ["github:pr:list", "github:issue:view"]
      }

      {:ok, preset} = ScopePreset.create(attrs)

      assert preset.name == "test-preset"
      assert preset.description == "Test description"
      assert preset.scopes == ["github:pr:list", "github:issue:view"]
      assert preset.is_system == false
    end

    test "creates system preset" do
      attrs = %{
        name: "system-preset",
        description: "System preset",
        scopes: ["*"],
        is_system: true
      }

      {:ok, preset} = ScopePreset.create(attrs)

      assert preset.is_system == true
    end

    test "enforces unique name constraint" do
      Factory.insert!(:scope_preset, %{name: "unique-name"})

      {:error, error} =
        ScopePreset.create(%{
          name: "unique-name",
          scopes: ["github:pr:list"]
        })

      assert Exception.message(error) =~ "has already been taken"
    end

    test "defaults scopes to empty list" do
      {:ok, preset} = ScopePreset.create(%{name: "empty-scopes"})

      assert preset.scopes == []
    end
  end

  describe "update/1" do
    test "updates non-system preset" do
      preset = Factory.insert!(:scope_preset, %{is_system: false})

      {:ok, updated} =
        ScopePreset.update(preset, %{
          name: "updated-name",
          scopes: ["github:*"]
        })

      assert updated.name == "updated-name"
      assert updated.scopes == ["github:*"]
    end

    test "prevents updating system preset" do
      preset = Factory.insert!(:scope_preset, %{is_system: true})

      {:error, error} = ScopePreset.update(preset, %{name: "new-name"})

      assert Exception.message(error) =~ "cannot modify system presets"
    end
  end

  describe "get_by_name/1" do
    test "returns preset by name" do
      Factory.insert!(:scope_preset, %{name: "find-me"})

      {:ok, preset} = ScopePreset.get_by_name("find-me")

      assert preset.name == "find-me"
    end

    test "returns error when not found" do
      {:error, _} = ScopePreset.get_by_name("nonexistent")
    end
  end

  describe "list/0" do
    test "returns all presets" do
      Factory.insert!(:scope_preset, %{name: "preset-1"})
      Factory.insert!(:scope_preset, %{name: "preset-2"})

      {:ok, presets} = ScopePreset.list()

      names = Enum.map(presets, & &1.name)
      assert "preset-1" in names
      assert "preset-2" in names
    end
  end

  describe "destroy/1" do
    test "destroys non-system preset" do
      preset = Factory.insert!(:scope_preset, %{is_system: false})

      :ok = ScopePreset.destroy(preset)

      {:error, _} = ScopePreset.get(preset.id)
    end
  end
end
