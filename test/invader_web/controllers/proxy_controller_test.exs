defmodule InvaderWeb.ProxyControllerTest do
  use InvaderWeb.ConnCase
  use Mimic

  alias Invader.Connections.GitHub.Executor
  alias Invader.Factory

  setup :verify_on_exit!

  setup do
    # Create a connection for tests
    connection = Factory.insert!(:connection)
    {:ok, connection: connection}
  end

  describe "run/2 with gh action" do
    test "allowed command returns 200 with output", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:list"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, args, _opts ->
        assert args == ["pr", "list", "--repo", "owner/repo"]
        {:ok, %{mode: :proxy, output: "PR #1 - Test PR"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "list", "--repo", "owner/repo"],
            "connection_id" => connection.id
          }
        })

      assert json_response(conn, 200) == %{
               "mode" => "proxy",
               "output" => "PR #1 - Test PR"
             }
    end

    test "forbidden scope returns 403 with permission denied", %{conn: conn} do
      mission = Factory.insert!(:mission, %{scopes: ["github:issue:view"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "list"]
          }
        })

      response = json_response(conn, 403)
      assert response["error"] == "Permission denied"
      assert response["scope"] == "github:pr:list"
      assert response["message"] =~ "does not have permission"
    end

    test "invalid token returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{"args" => ["pr", "list"]}
        })

      assert json_response(conn, 401) == %{"error" => "Invalid or expired token"}
    end

    test "missing token returns 401", %{conn: conn} do
      conn =
        conn
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{"args" => ["pr", "list"]}
        })

      assert json_response(conn, 401) == %{"error" => "Invalid or expired token"}
    end

    test "executor error returns 400", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["*"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:error, %{exit_code: 1, output: "Command failed"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "list"],
            "connection_id" => connection.id
          }
        })

      response = json_response(conn, 400)
      assert response["error"] == "Command failed"
      assert response["exit_code"] == 1
      assert response["output"] == "Command failed"
    end

    test "token mode returns token info", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["*"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:ok, %{mode: :token, token: "ghs_ephemeral", expires_at: "2024-12-31T23:59:59Z"}}
      end)

      conn =
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

      response = json_response(conn, 200)
      assert response["mode"] == "token"
      assert response["token"] == "ghs_ephemeral"
      assert response["expires_at"] == "2024-12-31T23:59:59Z"
    end

    test "no mission_id in token allows all commands (backward compat)", %{
      conn: conn,
      connection: connection
    } do
      token = Factory.generate_token(%{sprite_id: "test-sprite"})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:ok, %{mode: :proxy, output: "Success"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "merge", "123"],
            "connection_id" => connection.id
          }
        })

      assert json_response(conn, 200)["output"] == "Success"
    end

    test "empty args (help) is allowed", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:list"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, args, _opts ->
        assert args == []
        {:ok, %{mode: :proxy, output: "gh help output"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => [],
            "connection_id" => connection.id
          }
        })

      assert json_response(conn, 200)["output"] == "gh help output"
    end

    test "wildcard scopes allow matching commands", %{conn: conn, connection: connection} do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:*"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      expect(Executor, :execute, fn _conn, _args, _opts ->
        {:ok, %{mode: :proxy, output: "PR merged"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "gh",
          "input" => %{
            "args" => ["pr", "merge", "123"],
            "connection_id" => connection.id
          }
        })

      assert json_response(conn, 200)["output"] == "PR merged"
    end
  end

  describe "run/2 with unknown action" do
    test "returns 400 for unknown action", %{conn: conn} do
      token = Factory.generate_token(%{})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{
          "action" => "unknown"
        })

      assert json_response(conn, 400) == %{"error" => "Unknown action: unknown"}
    end
  end

  describe "run/2 with missing action" do
    test "returns 400 for missing action", %{conn: conn} do
      token = Factory.generate_token(%{})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/proxy", %{})

      assert json_response(conn, 400) == %{"error" => "Missing action parameter"}
    end
  end
end
