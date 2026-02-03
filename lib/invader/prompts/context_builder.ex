defmodule Invader.Prompts.ContextBuilder do
  @moduledoc """
  Builds CLI context blocks for injection into prompts.

  Generates XML-style context that informs Claude about available CLI commands
  based on the mission's scope configuration.
  """

  alias Invader.Scopes.Checker
  alias Invader.Scopes.Parsers.GitHub
  alias Invader.Scopes.Parsers.Telegram

  @doc """
  Builds a CLI capabilities context block for a mission.

  Returns an XML-style block that can be prepended to prompts.
  """
  def build(mission, bindings \\ %{}) do
    mission = Ash.load!(mission, :scope_preset)
    scopes = Checker.get_effective_scopes(mission)

    github_commands = build_github_commands(scopes)
    telegram_commands = build_telegram_commands(scopes)
    context_section = build_context_section(mission, bindings)

    """
    <cli_capabilities>
    You have access to the Invader CLI for various operations.

    #{github_commands}#{telegram_commands}
    #{context_section}
    </cli_capabilities>

    ---

    """
  end

  @doc """
  Builds just the available commands section without the full context wrapper.
  """
  def build_commands_only(scopes) do
    github = build_github_commands(scopes)
    telegram = build_telegram_commands(scopes)
    "#{github}#{telegram}"
  end

  defp build_github_commands(scopes) do
    if scopes == [] or scopes == nil or scopes == ["*"] do
      build_full_access_github_commands()
    else
      build_scoped_github_commands(scopes)
    end
  end

  defp build_full_access_github_commands do
    """
    ## GitHub Commands
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

  defp build_scoped_github_commands(scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)
    grouped = GitHub.group_by_category(allowed_scopes)

    if map_size(allowed_scopes) == 0 do
      ""
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
      ## GitHub Commands
      The following GitHub commands are available:

      #{command_sections}
      """
    end
  end

  defp build_telegram_commands(scopes) do
    if scopes == [] or scopes == nil or scopes == ["*"] do
      build_full_access_telegram_commands()
    else
      build_scoped_telegram_commands(scopes)
    end
  end

  defp build_full_access_telegram_commands do
    """
    ## Telegram Commands (Human-in-the-Loop)
    You can interact with the user via Telegram for human-in-the-loop workflows.

    Available commands:
    - `invader telegram ask "message"` - Send a message and wait for user reply (blocking)
    - `invader telegram notify "message"` - Send a notification (fire-and-forget)

    Options for 'ask':
    - `--timeout <ms>` - Timeout in milliseconds (default: 300000 = 5 min)

    Use these commands when you need human input, approval, or want to notify the user of progress.
    """
  end

  defp build_scoped_telegram_commands(scopes) do
    allowed_scopes = Telegram.filter_scopes(scopes)

    if map_size(allowed_scopes) == 0 do
      ""
    else
      commands =
        allowed_scopes
        |> Enum.sort_by(fn {scope, _} -> scope end)
        |> Enum.map(fn {_scope, info} ->
          "- `#{info.command}` - #{info.description}"
        end)
        |> Enum.join("\n")

      """
      ## Telegram Commands (Human-in-the-Loop)
      You can interact with the user via Telegram:

      #{commands}

      Options for 'ask':
      - `--timeout <ms>` - Timeout in milliseconds (default: 300000 = 5 min)

      Use these commands when you need human input, approval, or want to notify the user.
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
