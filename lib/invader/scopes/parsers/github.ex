defmodule Invader.Scopes.Parsers.GitHub do
  @moduledoc """
  Parses GitHub CLI arguments into scope strings.

  Converts `gh` command arguments like `["pr", "list", "--repo", "owner/repo"]`
  into scope strings like `"github:pr:list"`.
  """

  @doc """
  Parses gh CLI args into a scope string.

  ## Examples

      iex> GitHub.parse_args(["pr", "list", "--repo", "owner/repo"])
      {:ok, "github:pr:list"}

      iex> GitHub.parse_args(["issue", "view", "123"])
      {:ok, "github:issue:view"}

      iex> GitHub.parse_args(["repo", "clone", "owner/repo"])
      {:ok, "github:repo:clone"}

      iex> GitHub.parse_args([])
      {:error, :no_command}
  """
  def parse_args([]), do: {:error, :no_command}

  def parse_args([category | rest]) do
    action = extract_action(rest)
    scope = build_scope(category, action)
    {:ok, scope}
  end

  @doc """
  Returns all known GitHub scope definitions for help generation.
  """
  def all_scopes do
    %{
      "github:pr:list" => %{
        description: "List pull requests",
        command: "invader gh pr list --repo owner/repo",
        category: :read
      },
      "github:pr:view" => %{
        description: "View a pull request",
        command: "invader gh pr view <number> --repo owner/repo",
        category: :read
      },
      "github:pr:create" => %{
        description: "Create a pull request",
        command: "invader gh pr create --repo owner/repo",
        category: :write
      },
      "github:pr:merge" => %{
        description: "Merge a pull request",
        command: "invader gh pr merge <number> --repo owner/repo",
        category: :write
      },
      "github:pr:close" => %{
        description: "Close a pull request",
        command: "invader gh pr close <number> --repo owner/repo",
        category: :write
      },
      "github:pr:checkout" => %{
        description: "Check out a pull request locally",
        command: "invader gh pr checkout <number>",
        category: :write
      },
      "github:pr:diff" => %{
        description: "View pull request diff",
        command: "invader gh pr diff <number> --repo owner/repo",
        category: :read
      },
      "github:pr:review" => %{
        description: "Add a review to a pull request",
        command: "invader gh pr review <number> --repo owner/repo",
        category: :write
      },
      "github:pr:comment" => %{
        description: "Add a comment to a pull request",
        command: "invader gh pr comment <number> --repo owner/repo",
        category: :write
      },
      "github:issue:list" => %{
        description: "List issues",
        command: "invader gh issue list --repo owner/repo",
        category: :read
      },
      "github:issue:view" => %{
        description: "View an issue",
        command: "invader gh issue view <number> --repo owner/repo",
        category: :read
      },
      "github:issue:create" => %{
        description: "Create an issue",
        command: "invader gh issue create --repo owner/repo",
        category: :write
      },
      "github:issue:close" => %{
        description: "Close an issue",
        command: "invader gh issue close <number> --repo owner/repo",
        category: :write
      },
      "github:issue:comment" => %{
        description: "Add a comment to an issue",
        command: "invader gh issue comment <number> --repo owner/repo",
        category: :write
      },
      "github:repo:list" => %{
        description: "List repositories",
        command: "invader gh repo list [owner]",
        category: :read
      },
      "github:repo:view" => %{
        description: "View repository details",
        command: "invader gh repo view owner/repo",
        category: :read
      },
      "github:repo:clone" => %{
        description: "Clone a repository",
        command: "invader gh repo clone owner/repo",
        category: :write
      },
      "github:repo:fork" => %{
        description: "Fork a repository",
        command: "invader gh repo fork owner/repo",
        category: :write
      }
      # NOTE: The following scopes require additional GitHub App permissions not currently configured:
      # - github:release:* requires Contents permission (partial support via tags)
      # - github:workflow:* requires Actions permission
      # - github:run:* requires Actions permission
      # - github:api:* is intentionally excluded (too broad, security concern)
    }
  end

  @doc """
  Returns scope definitions filtered by allowed scopes.
  """
  def filter_scopes(allowed_scopes) do
    all_scopes()
    |> Enum.filter(fn {scope, _info} ->
      Invader.Scopes.Checker.allowed?(%{scopes: allowed_scopes}, scope)
    end)
    |> Map.new()
  end

  @doc """
  Groups scopes by category (pr, issue, repo, etc).
  """
  def group_by_category(scopes) do
    scopes
    |> Enum.group_by(fn {scope, _info} ->
      scope
      |> String.split(":")
      |> Enum.at(1)
    end)
  end

  # Extract the action from the remaining args (skip flags and values)
  defp extract_action([]), do: nil

  defp extract_action([arg | rest]) do
    cond do
      # Skip flags
      String.starts_with?(arg, "-") ->
        # Skip the next arg if this flag takes a value
        if takes_value?(arg) do
          extract_action(Enum.drop(rest, 1))
        else
          extract_action(rest)
        end

      # This looks like a subcommand/action
      String.match?(arg, ~r/^[a-z-]+$/) ->
        arg

      # Skip numeric args (issue/PR numbers)
      String.match?(arg, ~r/^\d+$/) ->
        extract_action(rest)

      # Skip repo-like args (owner/repo)
      String.contains?(arg, "/") ->
        extract_action(rest)

      # Default: treat as action
      true ->
        arg
    end
  end

  defp takes_value?(flag) do
    flag in ~w(--repo -R --state -s --label -l --assignee -a --author --limit -L)
  end

  defp build_scope(category, nil), do: "github:#{category}"
  defp build_scope(category, action), do: "github:#{category}:#{action}"
end
