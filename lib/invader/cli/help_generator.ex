defmodule Invader.CLI.HelpGenerator do
  @moduledoc """
  Generates help text for the Invader CLI based on allowed scopes.
  """

  alias Invader.Scopes.Parsers.GitHub

  @doc """
  Generates the main help text showing available commands based on scopes.
  """
  def generate_main_help(scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)
    categories = get_available_categories(allowed_scopes)

    lines = [
      "Invader CLI - GitHub proxy for sprites",
      "",
      "Usage: invader <command> [args...]",
      "",
      "Commands:"
    ]

    command_lines =
      if "gh" in categories do
        ["  gh    GitHub CLI commands"]
      else
        []
      end

    help_lines = [
      "",
      "Run 'invader <command> --help' for more information."
    ]

    Enum.join(lines ++ command_lines ++ help_lines, "\n")
  end

  @doc """
  Generates help for the gh command showing available subcommands.
  """
  def generate_gh_help(scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)
    grouped = GitHub.group_by_category(allowed_scopes)

    lines = [
      "GitHub CLI Commands",
      "",
      "Usage: invader gh <subcommand> [args...]",
      "",
      "Available subcommands:"
    ]

    subcommand_lines =
      grouped
      |> Enum.sort_by(fn {category, _} -> category end)
      |> Enum.map(fn {category, _scopes} ->
        "  #{String.pad_trailing(category, 12)}#{category_description(category)}"
      end)

    help_lines = [
      "",
      "Run 'invader gh <subcommand> --help' for more information."
    ]

    Enum.join(lines ++ subcommand_lines ++ help_lines, "\n")
  end

  @doc """
  Generates help for a specific gh subcommand (e.g., pr, issue).
  """
  def generate_gh_subcommand_help(subcommand, scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)
    grouped = GitHub.group_by_category(allowed_scopes)

    case Map.get(grouped, subcommand) do
      nil ->
        "Error: '#{subcommand}' is not available with your current permissions."

      scopes_in_category ->
        lines = [
          "GitHub #{String.capitalize(subcommand)} Commands",
          "",
          "Usage: invader gh #{subcommand} <action> [args...]",
          "",
          "Available actions:"
        ]

        action_lines =
          scopes_in_category
          |> Enum.sort_by(fn {scope, _} -> scope end)
          |> Enum.map(fn {_scope, info} ->
            action = extract_action_from_command(info.command, subcommand)
            "  #{String.pad_trailing(action, 12)}#{info.description}"
          end)

        examples = generate_examples(scopes_in_category, subcommand)

        Enum.join(lines ++ action_lines ++ [""] ++ examples, "\n")
    end
  end

  @doc """
  Generates a JSON structure with all help information for embedding in the CLI script.
  """
  def generate_help_json(scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)
    grouped = GitHub.group_by_category(allowed_scopes)

    subcommand_helps =
      grouped
      |> Enum.map(fn {category, _} ->
        {category, generate_gh_subcommand_help(category, scopes)}
      end)
      |> Map.new()

    %{
      "main" => generate_main_help(scopes),
      "gh" => generate_gh_help(scopes),
      "gh_subcommands" => subcommand_helps
    }
  end

  @doc """
  Generates a JSON structure of allowed commands for client-side validation.
  """
  def generate_allowed_commands_json(scopes) do
    allowed_scopes = GitHub.filter_scopes(scopes)

    commands =
      allowed_scopes
      |> Enum.map(fn {scope, _info} ->
        # Convert "github:pr:list" to ["pr", "list"]
        scope
        |> String.replace_prefix("github:", "")
        |> String.split(":")
      end)

    %{
      "allowed" => commands,
      "scopes" => scopes
    }
  end

  # Private helpers

  defp get_available_categories(allowed_scopes) do
    if map_size(allowed_scopes) > 0 do
      ["gh"]
    else
      []
    end
  end

  defp category_description(category) do
    case category do
      "pr" -> "Work with pull requests"
      "issue" -> "Work with issues"
      "repo" -> "Work with repositories"
      "release" -> "Work with releases"
      "workflow" -> "Work with GitHub Actions workflows"
      "run" -> "Work with workflow runs"
      "api" -> "Make API requests"
      _ -> "#{category} commands"
    end
  end

  defp extract_action_from_command(command, subcommand) do
    # Parse command like "invader gh pr list --repo owner/repo"
    # to extract "list"
    parts = String.split(command)

    case Enum.find_index(parts, &(&1 == subcommand)) do
      nil -> "unknown"
      idx -> Enum.at(parts, idx + 1, "unknown")
    end
  end

  defp generate_examples(scopes_in_category, _subcommand) do
    examples =
      scopes_in_category
      |> Enum.take(2)
      |> Enum.map(fn {_scope, info} -> "  #{info.command}" end)

    if examples == [] do
      []
    else
      ["Examples:" | examples]
    end
  end
end
