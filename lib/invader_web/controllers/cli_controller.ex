defmodule InvaderWeb.CliController do
  @moduledoc """
  Serves CLI scripts for sprites to download and install.
  """
  use InvaderWeb, :controller

  @doc """
  Serves the main invader CLI script.
  """
  def invader_script(conn, _params) do
    script = """
    #!/usr/bin/env bash
    set -euo pipefail

    # Configuration (set during installation)
    if [ -f ~/.config/invader/config ]; then
      source ~/.config/invader/config
    fi

    INVADER_URL="${INVADER_URL:-}"
    INVADER_TOKEN="${INVADER_TOKEN:-}"

    # Stateful commands that need token mode (run locally)
    STATEFUL_COMMANDS="clone|checkout|push|pull|fetch"

    usage() {
      echo "Invader CLI - GitHub proxy for sprites"
      echo ""
      echo "Usage: invader gh <command> [args...]"
      echo ""
      echo "Examples:"
      echo "  invader gh pr list --repo owner/repo"
      echo "  invader gh issue view 123 --repo owner/repo"
      echo "  invader gh repo clone owner/repo"
      echo ""
    }

    check_config() {
      if [ -z "$INVADER_URL" ] || [ -z "$INVADER_TOKEN" ]; then
        echo "Error: Invader not configured." >&2
        echo "Run the install script or set INVADER_URL and INVADER_TOKEN." >&2
        exit 1
      fi
    }

    # Call Invader API
    api_call() {
      local action="$1"
      local input="$2"

      curl -sS -X POST "${INVADER_URL}/api/proxy" \\
        -H "Content-Type: application/json" \\
        -H "Authorization: Bearer ${INVADER_TOKEN}" \\
        -d "{\\"action\\": \\"${action}\\", \\"input\\": ${input}}"
    }

    # Main gh command handler
    cmd_gh() {
      check_config

      if [ $# -eq 0 ]; then
        usage
        exit 1
      fi

      # Build JSON array of arguments
      local args_json="["
      local first=true
      for arg in "$@"; do
        if [ "$first" = true ]; then
          first=false
        else
          args_json+=","
        fi
        # Escape quotes in argument
        arg="${arg//\\\\/\\\\\\\\}"
        arg="${arg//\\"/\\\\\\"}"
        args_json+="\\"$arg\\""
      done
      args_json+="]"

      local cmd_string="$*"

      # Check if this is a stateful command
      local mode="proxy"
      if echo "$cmd_string" | grep -qE "$STATEFUL_COMMANDS"; then
        mode="token"
      fi

      local result
      result=$(api_call "gh" "{\\"args\\": ${args_json}, \\"mode\\": \\"${mode}\\"}")

      # Check for errors
      local error
      error=$(echo "$result" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"error"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/' || true)
      if [ -n "$error" ]; then
        echo "Error: $error" >&2
        exit 1
      fi

      local result_mode
      result_mode=$(echo "$result" | grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"mode"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/' || true)

      if [ "$result_mode" = "proxy" ]; then
        # Server executed, extract and print output
        # Use sed to extract the output field value
        echo "$result" | sed -n 's/.*"output"[[:space:]]*:[[:space:]]*"\\(.*\\)".*/\\1/p' | sed 's/\\\\n/\\n/g' | sed 's/\\\\t/\\t/g'
      elif [ "$result_mode" = "token" ]; then
        # Run locally with ephemeral token
        local token
        token=$(echo "$result" | grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/')
        GH_TOKEN="$token" gh "$@"
      else
        echo "Error: Unexpected response from server" >&2
        echo "$result" >&2
        exit 1
      fi
    }

    # Parse command
    case "${1:-}" in
      gh)
        shift
        cmd_gh "$@"
        ;;
      --help|-h|"")
        usage
        ;;
      *)
        echo "Unknown command: $1" >&2
        usage
        exit 1
        ;;
    esac
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, script)
  end

  @doc """
  Serves the installation script.
  """
  def install_script(conn, _params) do
    script = """
    #!/usr/bin/env bash
    set -euo pipefail

    INVADER_URL="${1:-}"
    INVADER_TOKEN="${2:-}"

    if [ -z "$INVADER_URL" ] || [ -z "$INVADER_TOKEN" ]; then
      echo "Usage: install.sh <invader_url> <token>"
      echo ""
      echo "Example:"
      echo "  curl -fsSL https://invader.example.com/cli/install.sh | bash -s -- https://invader.example.com my-token"
      exit 1
    fi

    echo "Installing Invader CLI..."

    # Download CLI script
    curl -fsSL "${INVADER_URL}/cli/invader.sh" -o /usr/local/bin/invader
    chmod +x /usr/local/bin/invader

    # Create config directory
    mkdir -p ~/.config/invader

    # Save configuration
    cat > ~/.config/invader/config <<EOF
    INVADER_URL="${INVADER_URL}"
    INVADER_TOKEN="${INVADER_TOKEN}"
    EOF

    echo ""
    echo "Invader CLI installed successfully!"
    echo ""
    echo "Test with:"
    echo "  invader gh pr list --repo owner/repo"
    echo ""
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, script)
  end
end
