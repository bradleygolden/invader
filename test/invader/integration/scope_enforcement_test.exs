defmodule Invader.Integration.ScopeEnforcementTest do
  @moduledoc """
  End-to-end integration tests for the scope enforcement system.

  Tests the complete flow from HTTP request through scope checking
  to mocked command execution.
  """
  use InvaderWeb.ConnCase
  use Mimic

  alias Invader.Connections.GitHub.Executor
  alias Invader.Factory

  setup :verify_on_exit!

  describe "complete scope enforcement flow" do
    setup do
      # Create all required resources via factory
      connection = Factory.insert!(:connection)
      sprite = Factory.insert!(:sprite)

      {:ok, connection: connection, sprite: sprite}
    end

    test "allowed command executes successfully", %{conn: conn, connection: connection} do
      # Create preset with limited scopes
      preset =
        Factory.insert!(:scope_preset, %{
          name: "read-only",
          scopes: ["github:pr:list", "github:pr:view", "github:issue:list"]
        })

      # Create mission using the preset
      mission = Factory.insert!(:mission, %{scope_preset_id: preset.id, scopes: nil})

      # Generate token for the mission
      token = Factory.generate_token(%{mission_id: mission.id})

      # Mock the executor to verify correct flow
      expect(Executor, :execute, fn conn, args, _opts ->
        assert conn.id == connection.id
        assert args == ["pr", "list", "--repo", "test/repo"]
        {:ok, %{mode: :proxy, output: "PR #1 - Test\nPR #2 - Another"}}
      end)

      # Make the proxy request
      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "list", "--repo", "test/repo"],
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["mode"] == "proxy"
      assert response["output"] =~ "PR #1"
    end

    test "forbidden command is blocked before execution", %{conn: conn, connection: connection} do
      # Create mission with limited scopes
      mission =
        Factory.insert!(:mission, %{
          scopes: ["github:pr:list", "github:issue:view"]
        })

      token = Factory.generate_token(%{mission_id: mission.id})

      # Make request for a forbidden command (pr:create is not in scopes)
      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "create", "--title", "New PR"],
            "connection_id" => connection.id
          }
        })
        |> json_response(403)

      assert response["error"] == "Permission denied"
      assert response["scope"] == "github:pr:create"
      assert response["message"] =~ "does not have permission"
    end

    test "wildcard scope allows category commands", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["github:issue:*"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, args, _opts ->
        assert args == ["issue", "create", "--title", "Bug report"]
        {:ok, %{mode: :proxy, output: "Created issue #42"}}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["issue", "create", "--title", "Bug report"],
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["output"] == "Created issue #42"
    end

    test "full access preset allows all commands", %{conn: conn, connection: connection} do
      preset = Factory.insert!(:scope_preset, %{scopes: ["*"]})
      mission = Factory.insert!(:mission, %{scope_preset_id: preset.id, scopes: nil})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, args, _opts ->
        assert args == ["pr", "merge", "123", "--admin"]
        {:ok, %{mode: :proxy, output: "Merged!"}}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "merge", "123", "--admin"],
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["output"] == "Merged!"
    end

    test "inline scopes override preset scopes", %{conn: conn, connection: connection} do
      # Preset allows all, but inline restricts to read-only
      preset = Factory.insert!(:scope_preset, %{scopes: ["*"]})

      mission =
        Factory.insert!(:mission, %{
          scope_preset_id: preset.id,
          scopes: ["github:pr:list"]
        })

      token = Factory.generate_token(%{mission_id: mission.id})

      # Try to merge - should be blocked by inline scopes
      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "merge", "123"],
            "connection_id" => connection.id
          }
        })
        |> json_response(403)

      assert response["error"] == "Permission denied"
      assert response["scope"] == "github:pr:merge"
    end

    test "token mode respects scopes", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["github:repo:clone"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, args, _opts ->
        assert args == ["repo", "clone", "owner/repo"]
        {:ok, %{mode: :token, token: "ghs_ephemeral", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["repo", "clone", "owner/repo"],
            "mode" => "token",
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["mode"] == "token"
      assert response["token"] == "ghs_ephemeral"
    end

    test "CLI script reflects mission scopes", %{conn: conn} do
      mission =
        Factory.insert!(:mission, %{
          scopes: ["github:pr:list", "github:pr:view"]
        })

      script =
        conn
        |> get("/cli/invader.sh", %{"mission_id" => mission.id})
        |> response(200)

      # Script should have pr commands
      assert script =~ "cmd_gh_pr"
      assert script =~ "list)"
      assert script =~ "view)"

      # Script should NOT have issue or repo handlers
      refute script =~ "cmd_gh_issue"
      refute script =~ "cmd_gh_repo"

      # Help text should reflect available commands
      assert script =~ "List pull requests"
      assert script =~ "View a pull request"
    end

    test "context builder generates correct prompt context", %{sprite: sprite} do
      preset =
        Factory.insert!(:scope_preset, %{
          scopes: ["github:issue:list", "github:issue:view"]
        })

      mission =
        Factory.insert!(:mission, %{
          sprite_id: sprite.id,
          scope_preset_id: preset.id,
          scopes: nil,
          max_waves: 10
        })

      context = Invader.Prompts.ContextBuilder.build(mission, %{wave_number: 3})

      # Should have CLI capabilities section
      assert context =~ "<cli_capabilities>"
      assert context =~ "</cli_capabilities>"

      # Should show only issue commands
      assert context =~ "Issue Commands"
      assert context =~ "invader gh issue list"
      assert context =~ "invader gh issue view"

      # Should NOT show PR or repo commands
      refute context =~ "invader gh pr"
      refute context =~ "invader gh repo"

      # Should show mission context
      assert context =~ "Wave: 3 of 10"
      assert context =~ "Remaining waves: 7"
    end
  end

  describe "backward compatibility" do
    setup do
      connection = Factory.insert!(:connection)
      {:ok, connection: connection}
    end

    test "no scopes configured allows all commands", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: nil, scope_preset_id: nil})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:ok, %{mode: :proxy, output: "Success"}}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "merge", "123", "--admin"],
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["output"] == "Success"
    end

    test "empty scopes list allows all commands", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: []})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:ok, %{mode: :proxy, output: "Success"}}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["repo", "delete", "owner/repo"],
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["output"] == "Success"
    end

    test "token without mission_id allows all commands", %{conn: conn, connection: connection} do
      # Old tokens might not have mission_id
      token = Factory.generate_token(%{sprite_id: "test-sprite"})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:ok, %{mode: :proxy, output: "Success"}}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "merge", "123"],
            "connection_id" => connection.id
          }
        })
        |> json_response(200)

      assert response["output"] == "Success"
    end
  end
end
