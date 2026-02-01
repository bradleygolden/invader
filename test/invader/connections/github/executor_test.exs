defmodule Invader.Connections.GitHub.ExecutorTest do
  use Invader.DataCase
  use Mimic

  alias Invader.Connections.GitHub.Executor
  alias Invader.Connections.GitHub.TokenGenerator
  alias Invader.Factory

  setup :verify_on_exit!

  describe "determine_mode/1" do
    test "returns :proxy for stateless commands" do
      assert Executor.determine_mode(["pr", "list"]) == :proxy
      assert Executor.determine_mode(["issue", "view", "123"]) == :proxy
      assert Executor.determine_mode(["pr", "create"]) == :proxy
    end

    test "returns :token for stateful commands" do
      assert Executor.determine_mode(["repo", "clone", "owner/repo"]) == :token
      assert Executor.determine_mode(["pr", "checkout", "123"]) == :token
    end
  end

  describe "execute/3" do
    test "proxy mode executes command and returns output" do
      connection = Factory.insert!(:connection)
      args = ["pr", "list", "--repo", "owner/repo"]

      expect(TokenGenerator, :generate_token, fn _conn ->
        {:ok, %{token: "ghs_test_token", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      expect(System, :cmd, fn "bash", ["-c", command], opts ->
        assert command == "gh pr list --repo owner/repo"
        assert Keyword.get(opts, :env) == [{"GH_TOKEN", "ghs_test_token"}]
        {"PR #1 - Test PR\nPR #2 - Another PR", 0}
      end)

      {:ok, result} = Executor.execute(connection, args)

      assert result.mode == :proxy
      assert result.output == "PR #1 - Test PR\nPR #2 - Another PR"
    end

    test "proxy mode returns error on command failure" do
      connection = Factory.insert!(:connection)
      args = ["pr", "list", "--repo", "nonexistent/repo"]

      expect(TokenGenerator, :generate_token, fn _conn ->
        {:ok, %{token: "ghs_test_token", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      expect(System, :cmd, fn "bash", ["-c", _command], _opts ->
        {"error: repository not found", 1}
      end)

      {:error, result} = Executor.execute(connection, args)

      assert result.exit_code == 1
      assert result.output == "error: repository not found"
    end

    test "token mode returns token without executing command" do
      connection = Factory.insert!(:connection)
      args = ["repo", "clone", "owner/repo"]

      expect(TokenGenerator, :generate_token, fn _conn ->
        {:ok, %{token: "ghs_test_token", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      {:ok, result} = Executor.execute(connection, args)

      assert result.mode == :token
      assert result.token == "ghs_test_token"
      assert result.expires_at == "2024-12-31T23:59:59Z"
    end

    test "force token mode with option" do
      connection = Factory.insert!(:connection)
      args = ["pr", "list"]

      expect(TokenGenerator, :generate_token, fn _conn ->
        {:ok, %{token: "ghs_test_token", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      {:ok, result} = Executor.execute(connection, args, mode: :token)

      assert result.mode == :token
      assert result.token == "ghs_test_token"
    end

    test "token generation failure returns error" do
      connection = Factory.insert!(:connection)
      args = ["pr", "list"]

      expect(TokenGenerator, :generate_token, fn _conn ->
        {:error, "GitHub API error (401): Bad credentials"}
      end)

      {:error, reason} = Executor.execute(connection, args)

      assert reason == "GitHub API error (401): Bad credentials"
    end

    test "logs request to audit trail" do
      connection = Factory.insert!(:connection)
      args = ["pr", "list"]

      expect(TokenGenerator, :generate_token, fn _conn ->
        {:ok, %{token: "ghs_test_token", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      expect(System, :cmd, fn "bash", ["-c", _command], _opts ->
        {"output", 0}
      end)

      {:ok, _result} = Executor.execute(connection, args, sprite_id: "test-sprite-id")

      # Verify request was logged
      {:ok, requests} = Invader.Connections.Request.list()
      request = Enum.find(requests, &(&1.command == "pr list"))

      assert request.connection_id == connection.id
      assert request.sprite_id == "test-sprite-id"
      assert request.mode == :proxy
      assert request.status == :completed
    end
  end
end
