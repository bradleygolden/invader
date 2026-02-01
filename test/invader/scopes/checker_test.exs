defmodule Invader.Scopes.CheckerTest do
  use Invader.DataCase

  alias Invader.Scopes.Checker
  alias Invader.Factory

  describe "scope_matches?/2" do
    test "exact match returns true" do
      assert Checker.scope_matches?("github:pr:list", "github:pr:list")
    end

    test "full wildcard matches everything" do
      assert Checker.scope_matches?("*", "github:pr:list")
      assert Checker.scope_matches?("*", "github:issue:view")
      assert Checker.scope_matches?("*", "linear:issue:create")
    end

    test "integration wildcard matches all in integration" do
      assert Checker.scope_matches?("github:*", "github:pr:list")
      assert Checker.scope_matches?("github:*", "github:issue:view")
      assert Checker.scope_matches?("github:*", "github:repo:clone")
    end

    test "category wildcard matches all in category" do
      assert Checker.scope_matches?("github:pr:*", "github:pr:list")
      assert Checker.scope_matches?("github:pr:*", "github:pr:view")
      assert Checker.scope_matches?("github:pr:*", "github:pr:create")
    end

    test "non-matching scopes return false" do
      refute Checker.scope_matches?("github:pr:list", "github:pr:view")
      refute Checker.scope_matches?("github:pr:*", "github:issue:list")
      refute Checker.scope_matches?("github:*", "linear:issue:view")
    end

    test "partial match does not work without wildcards" do
      refute Checker.scope_matches?("github:pr", "github:pr:list")
      refute Checker.scope_matches?("github", "github:pr:list")
    end
  end

  describe "allowed?/2" do
    test "scope in list returns true" do
      mission = %{scopes: ["github:pr:list", "github:issue:view"]}

      assert Checker.allowed?(mission, "github:pr:list")
      assert Checker.allowed?(mission, "github:issue:view")
    end

    test "scope not in list returns false" do
      mission = %{scopes: ["github:pr:list"]}

      refute Checker.allowed?(mission, "github:pr:create")
      refute Checker.allowed?(mission, "github:issue:view")
    end

    test "empty scopes allow all (backward compatibility)" do
      mission = %{scopes: []}

      assert Checker.allowed?(mission, "github:pr:list")
      assert Checker.allowed?(mission, "github:issue:create")
    end

    test "nil scopes allow all (backward compatibility)" do
      mission = %{scopes: nil}

      assert Checker.allowed?(mission, "github:pr:list")
    end

    test "wildcard expansion works" do
      mission = %{scopes: ["github:*"]}

      assert Checker.allowed?(mission, "github:pr:list")
      assert Checker.allowed?(mission, "github:issue:view")
      refute Checker.allowed?(mission, "linear:issue:view")
    end

    test "full wildcard allows everything" do
      mission = %{scopes: ["*"]}

      assert Checker.allowed?(mission, "github:pr:list")
      assert Checker.allowed?(mission, "linear:issue:view")
      assert Checker.allowed?(mission, "anything:at:all")
    end

    test "multiple wildcards work" do
      mission = %{scopes: ["github:pr:*", "github:issue:view"]}

      assert Checker.allowed?(mission, "github:pr:list")
      assert Checker.allowed?(mission, "github:pr:create")
      assert Checker.allowed?(mission, "github:issue:view")
      refute Checker.allowed?(mission, "github:issue:create")
    end
  end

  describe "get_effective_scopes/1" do
    test "inline scopes override preset" do
      preset = Factory.insert!(:scope_preset, %{scopes: ["github:pr:list"]})

      mission = %{
        scopes: ["github:issue:*"],
        scope_preset: preset
      }

      assert Checker.get_effective_scopes(mission) == ["github:issue:*"]
    end

    test "falls back to preset when inline empty" do
      preset = Factory.insert!(:scope_preset, %{scopes: ["github:pr:list", "github:issue:view"]})

      mission = %{
        scopes: [],
        scope_preset: preset
      }

      assert Checker.get_effective_scopes(mission) == ["github:pr:list", "github:issue:view"]
    end

    test "falls back to preset when inline nil" do
      preset = Factory.insert!(:scope_preset, %{scopes: ["github:*"]})

      mission = %{
        scopes: nil,
        scope_preset: preset
      }

      assert Checker.get_effective_scopes(mission) == ["github:*"]
    end

    test "returns empty list when no scopes configured" do
      mission = %{scopes: nil}

      assert Checker.get_effective_scopes(mission) == []
    end

    test "loads preset by ID when not preloaded" do
      preset = Factory.insert!(:scope_preset, %{scopes: ["github:repo:*"]})

      mission = %{
        scopes: nil,
        scope_preset_id: preset.id
      }

      assert Checker.get_effective_scopes(mission) == ["github:repo:*"]
    end

    test "returns empty list when preset ID not found" do
      mission = %{
        scopes: nil,
        scope_preset_id: Ecto.UUID.generate()
      }

      assert Checker.get_effective_scopes(mission) == []
    end
  end
end
