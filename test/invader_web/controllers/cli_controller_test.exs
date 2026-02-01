defmodule InvaderWeb.CliControllerTest do
  use InvaderWeb.ConnCase
  use Mimic

  alias Invader.Factory

  setup :verify_on_exit!

  describe "invader_script/2" do
    test "returns full access script without params", %{conn: conn} do
      conn = get(conn, "/cli/invader.sh")

      assert response(conn, 200) =~ "#!/usr/bin/env bash"
      assert response(conn, 200) =~ "show_main_help"
      assert response(conn, 200) =~ "show_gh_help"
      # Full access has pr, issue, repo commands
      assert response(conn, 200) =~ "cmd_gh_pr"
      assert response(conn, 200) =~ "cmd_gh_issue"
      assert response(conn, 200) =~ "cmd_gh_repo"
    end

    test "returns scoped script with mission_id", %{conn: conn} do
      mission =
        Factory.insert!(:mission, %{scopes: ["github:pr:list", "github:pr:view"]})

      conn = get(conn, "/cli/invader.sh", %{"mission_id" => mission.id})

      script = response(conn, 200)
      assert script =~ "#!/usr/bin/env bash"
      assert script =~ "cmd_gh_pr"
      # Only pr commands should be present
      assert script =~ "list)"
      assert script =~ "view)"
      # Should NOT have issue or repo handlers since not in scopes
      refute script =~ "cmd_gh_issue"
      refute script =~ "cmd_gh_repo"
    end

    test "returns scoped script with token", %{conn: conn} do
      mission = Factory.insert!(:mission, %{scopes: ["github:issue:*"]})
      token = Factory.generate_token(%{mission_id: mission.id})

      conn = get(conn, "/cli/invader.sh", %{"token" => token})

      script = response(conn, 200)
      assert script =~ "cmd_gh_issue"
      refute script =~ "cmd_gh_pr"
      refute script =~ "cmd_gh_repo"
    end

    test "invalid token returns full access fallback", %{conn: conn} do
      conn = get(conn, "/cli/invader.sh", %{"token" => "invalid-token"})

      script = response(conn, 200)
      # Should have all commands for full access
      assert script =~ "cmd_gh_pr"
      assert script =~ "cmd_gh_issue"
      assert script =~ "cmd_gh_repo"
    end

    test "expired token returns full access fallback", %{conn: conn} do
      # Create token that will be considered expired
      expired_token =
        Phoenix.Token.sign(InvaderWeb.Endpoint, "sprite_proxy", %{mission_id: "test"})

      # Mock verify to return error for expired
      expect(Phoenix.Token, :verify, fn _endpoint, _salt, _token, _opts ->
        {:error, :expired}
      end)

      conn = get(conn, "/cli/invader.sh", %{"token" => expired_token})

      script = response(conn, 200)
      # Full access fallback
      assert script =~ "cmd_gh_pr"
      assert script =~ "cmd_gh_issue"
    end

    test "script with preset-based scopes", %{conn: conn} do
      preset = Factory.insert!(:scope_preset, %{scopes: ["github:repo:*"]})
      mission = Factory.insert!(:mission, %{scopes: nil, scope_preset_id: preset.id})

      conn = get(conn, "/cli/invader.sh", %{"mission_id" => mission.id})

      script = response(conn, 200)
      assert script =~ "cmd_gh_repo"
      refute script =~ "cmd_gh_pr"
      refute script =~ "cmd_gh_issue"
    end

    test "script content type is text/plain", %{conn: conn} do
      conn = get(conn, "/cli/invader.sh")

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "script includes api_call function", %{conn: conn} do
      conn = get(conn, "/cli/invader.sh")

      script = response(conn, 200)
      assert script =~ "api_call()"
      assert script =~ "curl -sS -X POST"
      assert script =~ "/api/proxy"
    end

    test "script includes stateful commands detection", %{conn: conn} do
      conn = get(conn, "/cli/invader.sh")

      script = response(conn, 200)
      assert script =~ "STATEFUL_COMMANDS"
      assert script =~ "clone|checkout|push|pull|fetch"
    end
  end

  describe "install_script/2" do
    test "returns installation script", %{conn: conn} do
      conn = get(conn, "/cli/install.sh")

      script = response(conn, 200)
      assert script =~ "#!/usr/bin/env bash"
      assert script =~ "Installing Invader CLI"
      assert script =~ "curl -fsSL"
      assert script =~ "/cli/invader.sh"
      assert script =~ "chmod +x"
      assert script =~ "/usr/local/bin/invader"
      assert script =~ "~/.config/invader/config"
    end

    test "install script includes usage instructions", %{conn: conn} do
      conn = get(conn, "/cli/install.sh")

      script = response(conn, 200)
      assert script =~ "Usage: install.sh <invader_url> <token>"
      assert script =~ "Example:"
    end

    test "install script content type is text/plain", %{conn: conn} do
      conn = get(conn, "/cli/install.sh")

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end
  end

  describe "help text generation" do
    test "main help shows available categories", %{conn: conn} do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:*", "github:issue:*"]})

      conn = get(conn, "/cli/invader.sh", %{"mission_id" => mission.id})

      script = response(conn, 200)
      # Help text should include both pr and issue
      assert script =~ "Work with pull requests"
      assert script =~ "Work with issues"
    end

    test "category help shows available actions", %{conn: conn} do
      mission = Factory.insert!(:mission, %{scopes: ["github:pr:list", "github:pr:view"]})

      conn = get(conn, "/cli/invader.sh", %{"mission_id" => mission.id})

      script = response(conn, 200)
      # PR help should include list and view
      assert script =~ "GitHub Pr Commands"
      assert script =~ "List pull requests"
      assert script =~ "View a pull request"
    end

    test "no commands shows appropriate message", %{conn: conn} do
      mission = Factory.insert!(:mission, %{scopes: ["nonexistent:scope"]})

      conn = get(conn, "/cli/invader.sh", %{"mission_id" => mission.id})

      script = response(conn, 200)
      assert script =~ "No commands are available for this mission"
    end
  end
end
