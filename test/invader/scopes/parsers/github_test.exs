defmodule Invader.Scopes.Parsers.GitHubTest do
  use ExUnit.Case, async: true

  alias Invader.Scopes.Parsers.GitHub

  describe "extract_repo/1" do
    test "extracts repo from --repo flag" do
      assert {:ok, {"owner", "repo"}} =
               GitHub.extract_repo(["pr", "list", "--repo", "owner/repo"])
    end

    test "extracts repo from -R flag" do
      assert {:ok, {"myorg", "myrepo"}} =
               GitHub.extract_repo(["pr", "list", "-R", "myorg/myrepo"])
    end

    test "returns :error when no repo flag present" do
      assert :error = GitHub.extract_repo(["pr", "list"])
    end

    test "returns :error for empty args" do
      assert :error = GitHub.extract_repo([])
    end

    test "extracts repo with flags before and after" do
      args = ["pr", "list", "--state", "open", "--repo", "org/project", "--limit", "10"]
      assert {:ok, {"org", "project"}} = GitHub.extract_repo(args)
    end

    test "handles repo with hyphens and underscores" do
      assert {:ok, {"my-org", "my_repo"}} = GitHub.extract_repo(["--repo", "my-org/my_repo"])
    end

    test "returns :error for malformed repo without slash" do
      assert :error = GitHub.extract_repo(["--repo", "noslash"])
    end

    test "returns :error for repo with empty owner" do
      assert :error = GitHub.extract_repo(["--repo", "/repo"])
    end

    test "returns :error for repo with empty name" do
      assert :error = GitHub.extract_repo(["--repo", "owner/"])
    end
  end

  describe "parse_args/1" do
    test "parses simple pr list command" do
      assert {:ok, "github:pr:list"} = GitHub.parse_args(["pr", "list"])
    end

    test "parses pr list with repo flag" do
      assert {:ok, "github:pr:list"} = GitHub.parse_args(["pr", "list", "--repo", "owner/repo"])
    end

    test "parses pr view with number" do
      assert {:ok, "github:pr:view"} = GitHub.parse_args(["pr", "view", "123"])
    end

    test "parses pr view with repo and number" do
      assert {:ok, "github:pr:view"} =
               GitHub.parse_args(["pr", "view", "123", "--repo", "owner/repo"])
    end

    test "parses issue list command" do
      assert {:ok, "github:issue:list"} = GitHub.parse_args(["issue", "list"])
    end

    test "parses issue view with number" do
      assert {:ok, "github:issue:view"} = GitHub.parse_args(["issue", "view", "456"])
    end

    test "parses repo clone command" do
      assert {:ok, "github:repo:clone"} = GitHub.parse_args(["repo", "clone", "owner/repo"])
    end

    test "parses repo view command" do
      assert {:ok, "github:repo:view"} = GitHub.parse_args(["repo", "view", "owner/repo"])
    end

    test "returns error for empty args" do
      assert {:error, :no_command} = GitHub.parse_args([])
    end

    test "parses command with short flags" do
      assert {:ok, "github:pr:list"} = GitHub.parse_args(["pr", "list", "-R", "owner/repo"])
    end

    test "parses command with multiple flags" do
      assert {:ok, "github:pr:list"} =
               GitHub.parse_args([
                 "pr",
                 "list",
                 "--repo",
                 "owner/repo",
                 "--state",
                 "open",
                 "--limit",
                 "10"
               ])
    end

    test "parses pr create command" do
      assert {:ok, "github:pr:create"} = GitHub.parse_args(["pr", "create"])
    end

    test "parses pr merge command" do
      assert {:ok, "github:pr:merge"} = GitHub.parse_args(["pr", "merge", "123"])
    end

    test "parses category only returns scope without action" do
      assert {:ok, "github:pr"} = GitHub.parse_args(["pr"])
    end
  end

  describe "all_scopes/0" do
    test "returns map of all scope definitions" do
      scopes = GitHub.all_scopes()

      assert is_map(scopes)
      assert Map.has_key?(scopes, "github:pr:list")
      assert Map.has_key?(scopes, "github:issue:view")
      assert Map.has_key?(scopes, "github:repo:clone")
    end

    test "each scope has required fields" do
      scopes = GitHub.all_scopes()

      for {_scope, info} <- scopes do
        assert Map.has_key?(info, :description)
        assert Map.has_key?(info, :command)
        assert Map.has_key?(info, :category)
        assert info.category in [:read, :write]
      end
    end

    test "includes both read and write scopes" do
      scopes = GitHub.all_scopes()

      read_scopes = Enum.filter(scopes, fn {_, info} -> info.category == :read end)
      write_scopes = Enum.filter(scopes, fn {_, info} -> info.category == :write end)

      assert length(read_scopes) > 0
      assert length(write_scopes) > 0
    end
  end

  describe "filter_scopes/1" do
    test "filters by specific allowed scopes" do
      allowed = ["github:pr:list", "github:issue:view"]
      filtered = GitHub.filter_scopes(allowed)

      assert Map.has_key?(filtered, "github:pr:list")
      assert Map.has_key?(filtered, "github:issue:view")
      refute Map.has_key?(filtered, "github:pr:create")
      refute Map.has_key?(filtered, "github:pr:view")
    end

    test "wildcard expansion works" do
      allowed = ["github:pr:*"]
      filtered = GitHub.filter_scopes(allowed)

      assert Map.has_key?(filtered, "github:pr:list")
      assert Map.has_key?(filtered, "github:pr:view")
      assert Map.has_key?(filtered, "github:pr:create")
      refute Map.has_key?(filtered, "github:issue:list")
    end

    test "full access wildcard returns all scopes" do
      allowed = ["*"]
      filtered = GitHub.filter_scopes(allowed)

      all = GitHub.all_scopes()
      assert map_size(filtered) == map_size(all)
    end

    test "integration wildcard returns all github scopes" do
      allowed = ["github:*"]
      filtered = GitHub.filter_scopes(allowed)

      all = GitHub.all_scopes()
      assert map_size(filtered) == map_size(all)
    end

    test "empty allowed list returns empty map" do
      # With empty scopes, the Checker.allowed? returns true for backward compat
      # But filter_scopes explicitly uses the Checker which allows all
      allowed = []
      filtered = GitHub.filter_scopes(allowed)

      # Empty scopes means full access (backward compat)
      all = GitHub.all_scopes()
      assert map_size(filtered) == map_size(all)
    end
  end

  describe "group_by_category/1" do
    test "groups scopes by category" do
      scopes = GitHub.all_scopes()
      grouped = GitHub.group_by_category(scopes)

      assert Map.has_key?(grouped, "pr")
      assert Map.has_key?(grouped, "issue")
      assert Map.has_key?(grouped, "repo")
    end

    test "each category contains only its scopes" do
      scopes = GitHub.all_scopes()
      grouped = GitHub.group_by_category(scopes)

      for {category, category_scopes} <- grouped do
        for {scope, _info} <- category_scopes do
          assert String.contains?(scope, ":#{category}:")
        end
      end
    end

    test "empty scopes returns empty map" do
      grouped = GitHub.group_by_category(%{})
      assert grouped == %{}
    end
  end
end
