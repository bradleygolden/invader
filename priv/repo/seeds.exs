# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Invader.Repo.insert!(%Invader.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Invader.Scopes.ScopePreset

# Built-in scope presets
# NOTE: Only includes scopes for currently configured GitHub App permissions:
# - Contents: Read & Write
# - Issues: Read & Write
# - Pull requests: Read & Write
# - Metadata: Read-only
# - Telegram: Human-in-the-loop interaction
scope_presets = [
  %{
    name: "full-access",
    description: "Full access to all operations (GitHub, Telegram, etc.)",
    scopes: ["*"],
    is_system: true
  },
  %{
    name: "github-read-only",
    description: "Read-only access to GitHub PRs, issues, and repos",
    scopes: [
      "github:pr:list",
      "github:pr:view",
      "github:pr:diff",
      "github:issue:list",
      "github:issue:view",
      "github:repo:list",
      "github:repo:view"
    ],
    is_system: true
  },
  %{
    name: "github-contributor",
    description: "Contributor access: PRs, issues, and repo cloning",
    scopes: [
      "github:pr:*",
      "github:issue:*",
      "github:repo:clone",
      "github:repo:list",
      "github:repo:view"
    ],
    is_system: true
  },
  %{
    name: "github-maintainer",
    description: "Full write access to supported GitHub operations (PRs, issues, repos)",
    scopes: [
      "github:pr:*",
      "github:issue:*",
      "github:repo:*"
    ],
    is_system: true
  },
  # Telegram presets
  %{
    name: "telegram-only",
    description: "Telegram human-in-the-loop interaction only (ask questions, send notifications)",
    scopes: [
      "telegram:*"
    ],
    is_system: true
  },
  %{
    name: "github-contributor-interactive",
    description: "GitHub contributor access with Telegram human-in-the-loop",
    scopes: [
      "github:pr:*",
      "github:issue:*",
      "github:repo:clone",
      "github:repo:list",
      "github:repo:view",
      "telegram:*"
    ],
    is_system: true
  },
  %{
    name: "github-maintainer-interactive",
    description: "GitHub maintainer access with Telegram human-in-the-loop",
    scopes: [
      "github:pr:*",
      "github:issue:*",
      "github:repo:*",
      "telegram:*"
    ],
    is_system: true
  }
]

for preset <- scope_presets do
  case ScopePreset.get_by_name(preset.name) do
    {:ok, existing} ->
      IO.puts("Scope preset '#{preset.name}' already exists, skipping...")

    {:error, _} ->
      ScopePreset.create!(preset)
      IO.puts("Created scope preset: #{preset.name}")
  end
end
