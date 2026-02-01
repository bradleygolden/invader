defmodule Invader.Prompts.ContextBuilderTest do
  use Invader.DataCase

  alias Invader.Prompts.ContextBuilder
  alias Invader.Factory

  describe "build/2" do
    test "builds full access context when no scopes" do
      mission = Factory.insert!(:mission, %{scopes: nil, max_waves: 20})

      context = ContextBuilder.build(mission)

      assert context =~ "<cli_capabilities>"
      assert context =~ "</cli_capabilities>"
      assert context =~ "full access to all GitHub CLI commands"
      assert context =~ "invader gh pr list"
      assert context =~ "invader gh --help"
    end

    test "builds full access context when scopes is empty list" do
      mission = Factory.insert!(:mission, %{scopes: [], max_waves: 20})

      context = ContextBuilder.build(mission)

      assert context =~ "full access to all GitHub CLI commands"
    end

    test "builds full access context when scopes is [*]" do
      mission = Factory.insert!(:mission, %{scopes: ["*"], max_waves: 20})

      context = ContextBuilder.build(mission)

      assert context =~ "full access to all GitHub CLI commands"
    end

    test "builds scoped context with specific commands" do
      mission =
        Factory.insert!(:mission, %{
          scopes: ["github:pr:list", "github:issue:view"],
          max_waves: 10
        })

      context = ContextBuilder.build(mission)

      assert context =~ "<cli_capabilities>"
      assert context =~ "The following commands are available"
      assert context =~ "invader gh pr list --repo owner/repo"
      assert context =~ "invader gh issue view"
      assert context =~ "Commands not listed above are not permitted"
      refute context =~ "invader gh pr create"
    end

    test "builds context with wildcard scopes" do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:*"], max_waves: 10})

      context = ContextBuilder.build(mission)

      assert context =~ "Pr Commands"
      assert context =~ "invader gh pr list"
      assert context =~ "invader gh pr view"
      assert context =~ "invader gh pr create"
      refute context =~ "Issue Commands"
    end

    test "includes mission context section" do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:*"], max_waves: 15})

      context = ContextBuilder.build(mission, %{wave_number: 5})

      assert context =~ "## Current Mission Context"
      assert context =~ "Mission ID: #{mission.id}"
      assert context =~ "Wave: 5 of 15"
      assert context =~ "Remaining waves: 10"
    end

    test "shows no commands message when scopes block everything" do
      mission =
        Factory.insert!(:mission, %{scopes: ["nonexistent:scope:here"], max_waves: 10})

      context = ContextBuilder.build(mission)

      assert context =~ "No GitHub commands are available for this mission"
    end

    test "loads scope_preset and uses its scopes" do
      preset = Factory.insert!(:scope_preset, %{scopes: ["github:repo:*"]})

      mission =
        Factory.insert!(:mission, %{scopes: nil, scope_preset_id: preset.id, max_waves: 5})

      context = ContextBuilder.build(mission)

      assert context =~ "Repo Commands"
      assert context =~ "invader gh repo list"
      assert context =~ "invader gh repo clone"
    end
  end

  describe "build_commands_only/1" do
    test "returns just the commands section for full access" do
      commands = ContextBuilder.build_commands_only(["*"])

      assert commands =~ "## Available Commands"
      assert commands =~ "full access to all GitHub CLI commands"
      refute commands =~ "Current Mission Context"
    end

    test "returns scoped commands without context" do
      commands = ContextBuilder.build_commands_only(["github:issue:list"])

      assert commands =~ "## Available Commands"
      assert commands =~ "invader gh issue list"
      refute commands =~ "Current Mission Context"
    end
  end
end
