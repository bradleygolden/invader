defmodule Invader.Prompts.ContextBuilder do
  @moduledoc """
  Builds CLI context blocks for injection into prompts.

  Generates XML-style context that informs Claude about available CLI commands
  based on the mission's scope configuration.
  """

  alias Invader.Scopes.Checker
  alias Invader.Scopes.Parsers.GitHub

  @doc """
  Builds a CLI capabilities context block for a mission.

  Returns an XML-style block that can be prepended to prompts.
  """
  def build(mission, bindings \\ %{}) do
    mission = Ash.load!(mission, :scope_preset)
    scopes = Checker.get_effective_scopes(mission)

    commands = build_command_list(scopes)
    context_section = build_context_section(mission, bindings)

    """
    <cli_capabilities>
    You have access to the Invader CLI for GitHub operations.

    #{commands}
    #{context_section}
    </cli_capabilities>

    ---

    """
  end

  @doc """
  Builds just the available commands section without the full context wrapper.
  """
  def build_commands_only(scopes) do
    build_command_list(scopes)
  end

  defp build_command_list(scopes) do
    if scopes == [] or scopes == nil or scopes == ["*"] do
      build_full_access_commands()
    else
      build_scoped_commands(scopes)
    end
  end

  defp build_full_access_commands do
    """
    ## Available Commands
    You have full access to all GitHub CLI commands via `invader gh`.

    Common commands:
    - `invader gh pr list --repo owner/repo` - List pull requests
    - `invader gh pr view <number> --repo owner/repo` - View a pull request
    - `invader gh pr create --repo owner/repo` - Create a pull request
    - `invader gh issue list --repo owner/repo` - List issues
    - `invader gh issue view <number> --repo owner/repo` - View an issue
    - `invader gh issue create --repo owner/repo` - Create an issue
    - `invader gh repo clone owner/repo` - Clone a repository

    Run `invader gh --help` for more commands.
    """
  end

  defp build_scoped_commands(scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)
    grouped = GitHub.group_by_category(allowed_scopes)

    if map_size(allowed_scopes) == 0 do
      """
      ## Available Commands
      No GitHub commands are available for this mission.
      """
    else
      command_sections =
        grouped
        |> Enum.sort_by(fn {category, _} -> category end)
        |> Enum.map(fn {category, category_scopes} ->
          commands =
            category_scopes
            |> Enum.sort_by(fn {scope, _} -> scope end)
            |> Enum.map(fn {_scope, info} ->
              "- `#{info.command}` - #{info.description}"
            end)
            |> Enum.join("\n")

          """
          ### #{String.capitalize(category)} Commands
          #{commands}
          """
        end)
        |> Enum.join("\n")

      """
      ## Available Commands
      The following commands are available for this mission:

      #{command_sections}
      **Note:** Commands not listed above are not permitted for this mission.
      """
    end
  end

  defp build_context_section(mission, bindings) do
    wave_number = Map.get(bindings, :wave_number, mission.current_wave + 1)
    max_waves = mission.max_waves

    """
    ## Current Mission Context
    - Mission ID: #{mission.id}
    - Wave: #{wave_number} of #{max_waves}
    - Remaining waves: #{max(0, max_waves - wave_number)}
    """
  end
end
