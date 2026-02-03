defmodule InvaderWeb.CliController do
  @moduledoc """
  Serves CLI scripts for sprites to download and install.
  """
  use InvaderWeb, :controller

  alias Invader.Missions.Mission
  alias Invader.Scopes.Checker

  @doc """
  Serves the main invader CLI script.

  Optionally accepts mission_id parameter to generate scope-aware help.
  """
  def invader_script(conn, params) do
    scopes = get_scopes_from_params(params)
    script = generate_script(scopes)

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

    # Download CLI script with token for scope-aware help
    curl -fsSL "${INVADER_URL}/cli/invader.sh?token=${INVADER_TOKEN}" -o /usr/local/bin/invader
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
    echo "  invader --help"
    echo ""
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, script)
  end

  @doc """
  Serves the update script for existing Invader installations.

  Preserves the SQLite database and configuration while updating the release.
  """
  def update_script(conn, _params) do
    script = generate_update_script()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, script)
  end

  defp generate_update_script do
    ~S"""
    #!/usr/bin/env bash
    set -euo pipefail

    VERSION="${1:-latest}"
    INVADER_DIR="${HOME}/invader"
    BACKUP_DIR="${HOME}/invader.backup.$(date +%s)"
    DATABASE_FILE="${HOME}/invader.db"
    ENV_FILE="${HOME}/.env"

    echo "═══════════════════════════════════════════════════════════════"
    echo "  Invader Update Script"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Updating to: ${VERSION}"
    echo ""

    # 1. Check current installation exists
    if [ ! -d "$INVADER_DIR" ]; then
      echo "Error: No existing installation at $INVADER_DIR"
      echo "Run the install script first."
      exit 1
    fi

    # 2. Verify database and config exist (these will be preserved)
    echo "Checking existing files..."
    if [ -f "$DATABASE_FILE" ]; then
      echo "  ✓ Database: $DATABASE_FILE (will be preserved)"
    else
      echo "  ⚠ Database not found at $DATABASE_FILE"
    fi

    if [ -f "$ENV_FILE" ]; then
      echo "  ✓ Config: $ENV_FILE (will be preserved)"
    else
      echo "  ✗ Error: Config file $ENV_FILE not found"
      exit 1
    fi

    # 3. Stop the running daemon
    echo ""
    echo "Stopping Invader daemon..."
    if [ -f "$INVADER_DIR/bin/invader" ]; then
      "$INVADER_DIR/bin/invader" stop 2>/dev/null || true
      sleep 2
    fi

    # 4. Backup current release (NOT the database or config)
    echo "Backing up current release to: $BACKUP_DIR"
    mv "$INVADER_DIR" "$BACKUP_DIR"

    # 5. Download new release
    echo ""
    echo "Downloading new release..."
    if [ "$VERSION" = "latest" ]; then
      DOWNLOAD_URL="https://github.com/bradleygolden/invader/releases/latest/download/invader.tar.gz"
    else
      DOWNLOAD_URL="https://github.com/bradleygolden/invader/releases/download/${VERSION}/invader.tar.gz"
    fi

    if ! curl -fsSL "$DOWNLOAD_URL" -o /tmp/invader.tar.gz; then
      echo "Error: Failed to download release"
      echo "Restoring backup..."
      mv "$BACKUP_DIR" "$INVADER_DIR"
      "$INVADER_DIR/bin/invader" daemon
      exit 1
    fi

    # 6. Extract new release
    echo "Extracting new release..."
    tar -xzf /tmp/invader.tar.gz -C "$HOME"
    rm /tmp/invader.tar.gz

    # 7. Run migrations (database is preserved, just apply new migrations)
    echo ""
    echo "Running database migrations..."
    set -a && source "$ENV_FILE" && set +a
    "$INVADER_DIR/bin/invader" eval 'for repo <- Application.fetch_env!(:invader, :ecto_repos), do: Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))'

    # 8. Start new daemon
    echo ""
    echo "Starting new daemon..."
    "$INVADER_DIR/bin/invader" daemon

    # 9. Verify running
    echo "Waiting for application to start..."
    for i in {1..15}; do
      if "$INVADER_DIR/bin/invader" pid > /dev/null 2>&1; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  ✅ Update successful!"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "  Database preserved: $DATABASE_FILE"
        echo "  Config preserved:   $ENV_FILE"
        echo "  Release backup:     $BACKUP_DIR"
        echo ""
        echo "  To remove backup: rm -rf $BACKUP_DIR"
        exit 0
      fi
      sleep 1
    done

    echo ""
    echo "⚠ Warning: Application may still be starting."
    echo "Check logs: $INVADER_DIR/bin/invader remote"
    echo ""
    echo "To rollback:"
    echo "  $INVADER_DIR/bin/invader stop"
    echo "  rm -rf $INVADER_DIR"
    echo "  mv $BACKUP_DIR $INVADER_DIR"
    echo "  $INVADER_DIR/bin/invader daemon"

    # 10. Update CLI wrapper (optional, if token available)
    if [ -f ~/.config/invader/config ]; then
      source ~/.config/invader/config
      if [ -n "${INVADER_URL:-}" ] && [ -n "${INVADER_TOKEN:-}" ]; then
        echo ""
        echo "Updating CLI wrapper..."
        curl -fsSL "${INVADER_URL}/cli/invader.sh?token=${INVADER_TOKEN}" -o /usr/local/bin/invader
        chmod +x /usr/local/bin/invader
      fi
    fi
    """
  end

  defp get_scopes_from_params(%{"token" => token}) when is_binary(token) and token != "" do
    case Phoenix.Token.verify(InvaderWeb.Endpoint, "sprite_proxy", token, max_age: 86400) do
      {:ok, %{mission_id: mission_id}} when is_binary(mission_id) ->
        case Mission.get(mission_id) do
          {:ok, mission} ->
            mission = Ash.load!(mission, :scope_preset)
            Checker.get_effective_scopes(mission)

          _ ->
            # Default to full access
            ["*"]
        end

      _ ->
        # Default to full access
        ["*"]
    end
  end

  defp get_scopes_from_params(%{"mission_id" => mission_id}) when is_binary(mission_id) do
    case Mission.get(mission_id) do
      {:ok, mission} ->
        mission = Ash.load!(mission, :scope_preset)
        Checker.get_effective_scopes(mission)

      _ ->
        ["*"]
    end
  end

  defp get_scopes_from_params(_), do: ["*"]

  defp generate_script(scopes) do
    alias Invader.Scopes.Parsers.GitHub
    alias Invader.Scopes.Parsers.Telegram

    allowed_scopes = GitHub.filter_scopes(scopes)
    grouped = GitHub.group_by_category(allowed_scopes)

    # Check which Telegram operations are allowed
    telegram_scopes = Telegram.filter_scopes(scopes)
    has_telegram = map_size(telegram_scopes) > 0

    # Generate category handlers (pr, issue, repo, etc.)
    category_handlers = generate_category_handlers(grouped)
    category_case = generate_category_case(grouped)
    main_help = generate_main_help_text(grouped, has_telegram)
    gh_help = generate_gh_help_text(grouped)

    telegram_functions =
      if has_telegram, do: generate_telegram_functions(telegram_scopes), else: ""

    telegram_case =
      if has_telegram,
        do: "    telegram)\n      shift\n      cmd_telegram \"$@\"\n      ;;",
        else: ""

    """
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

    show_main_help() {
      cat <<'HELPEOF'
    #{main_help}
    HELPEOF
    }

    show_gh_help() {
      cat <<'HELPEOF'
    #{gh_help}
    HELPEOF
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

    # Execute a gh command through the proxy
    run_gh_command() {
      check_config

      # Build JSON array of arguments
      local args_json="["
      local first=true
      for arg in "$@"; do
        if [ "$first" = true ]; then
          first=false
        else
          args_json+=","
        fi
        # Escape quotes and backslashes in argument
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

      # Check for errors (use jq for robust JSON parsing)
      local error
      error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null || true)
      if [ -n "$error" ]; then
        echo "Error: $error" >&2
        local message exit_code output
        message=$(echo "$result" | jq -r '.message // empty' 2>/dev/null || true)
        exit_code=$(echo "$result" | jq -r '.exit_code // empty' 2>/dev/null || true)
        output=$(echo "$result" | jq -r '.output // empty' 2>/dev/null || true)
        [ -n "$message" ] && echo "$message" >&2
        [ -n "$exit_code" ] && echo "Exit code: $exit_code" >&2
        [ -n "$output" ] && echo "$output" >&2
        exit 1
      fi

      local result_mode
      result_mode=$(echo "$result" | jq -r '.mode // empty' 2>/dev/null || true)

      if [ "$result_mode" = "proxy" ]; then
        echo "$result" | jq -r '.output // empty'
      elif [ "$result_mode" = "token" ]; then
        local token
        token=$(echo "$result" | jq -r '.token // empty' 2>/dev/null)
        GH_TOKEN="$token" gh "$@"
      else
        echo "Error: Unexpected response from server" >&2
        echo "$result" >&2
        exit 1
      fi
    }

    #{category_handlers}

    # Main gh command handler
    cmd_gh() {
      if [ $# -eq 0 ]; then
        show_gh_help
        exit 0
      fi

      case "$1" in
        --help|-h)
          show_gh_help
          exit 0
          ;;
    #{category_case}
        *)
          echo "Unknown command: gh $1" >&2
          echo "Run 'invader gh --help' for available commands." >&2
          exit 1
          ;;
      esac
    }

    #{telegram_functions}

    # Parse command
    case "${1:-}" in
      gh)
        shift
        cmd_gh "$@"
        ;;
    #{telegram_case}
      --help|-h|"")
        show_main_help
        ;;
      *)
        echo "Unknown command: $1" >&2
        show_main_help
        exit 1
        ;;
    esac
    """
  end

  defp generate_telegram_functions(telegram_scopes) do
    has_ask = Map.has_key?(telegram_scopes, "telegram:ask")
    has_notify = Map.has_key?(telegram_scopes, "telegram:notify")
    has_send_document = Map.has_key?(telegram_scopes, "telegram:send_document")

    ask_help =
      if has_ask, do: "  ask <message>       Send a message and wait for user reply", else: ""

    notify_help =
      if has_notify, do: "  notify <message>    Send a notification (fire-and-forget)", else: ""

    send_document_help =
      if has_send_document, do: "  send-document <file> Share a document with the user", else: ""

    commands_help =
      [ask_help, notify_help, send_document_help] |> Enum.reject(&(&1 == "")) |> Enum.join("\n")

    ask_case =
      if has_ask,
        do: """
            ask)
              shift
              telegram_ask "$@"
              ;;
        """,
        else: ""

    notify_case =
      if has_notify,
        do: """
            notify)
              shift
              telegram_notify "$@"
              ;;
        """,
        else: ""

    send_document_case =
      if has_send_document,
        do: """
            send-document)
              shift
              telegram_send_document "$@"
              ;;
        """,
        else: ""

    ask_function =
      if has_ask,
        do: """
        telegram_ask() {
          local message=""
          local timeout=""

          while [ $# -gt 0 ]; do
            case "$1" in
              --timeout)
                timeout="$2"
                shift 2
                ;;
              *)
                if [ -z "$message" ]; then
                  message="$1"
                else
                  message="$message $1"
                fi
                shift
                ;;
            esac
          done

          if [ -z "$message" ]; then
            echo "Error: Message is required" >&2
            echo "Usage: invader telegram ask <message> [--timeout <ms>]" >&2
            exit 1
          fi

          # Escape message for JSON
          message="${message//\\\\/\\\\\\\\}"
          message="${message//\\"/\\\\\\"}"
          message="${message//$'\\n'/\\\\n}"

          local input="{\\"operation\\": \\"ask\\", \\"message\\": \\"${message}\\""
          if [ -n "$timeout" ]; then
            input+=", \\"timeout\\": ${timeout}"
          fi
          input+="}"

          local result
          result=$(api_call "telegram" "$input")

          local error
          error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null || true)
          if [ -n "$error" ]; then
            local err_message
            err_message=$(echo "$result" | jq -r '.message // empty' 2>/dev/null || true)
            if [ "$error" = "timeout" ]; then
              echo "Timeout: No response received" >&2
              exit 124  # Standard timeout exit code
            else
              echo "Error: $error" >&2
              [ -n "$err_message" ] && echo "$err_message" >&2
              exit 1
            fi
          fi

          echo "$result" | jq -r '.response // empty'
        }
        """,
        else: ""

    notify_function =
      if has_notify,
        do: """
        telegram_notify() {
          local message="$*"

          if [ -z "$message" ]; then
            echo "Error: Message is required" >&2
            echo "Usage: invader telegram notify <message>" >&2
            exit 1
          fi

          # Escape message for JSON
          message="${message//\\\\/\\\\\\\\}"
          message="${message//\\"/\\\\\\"}"
          message="${message//$'\\n'/\\\\n}"

          local result
          result=$(api_call "telegram" "{\\"operation\\": \\"notify\\", \\"message\\": \\"${message}\\"}")

          local error
          error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null || true)
          if [ -n "$error" ]; then
            echo "Error: $error" >&2
            exit 1
          fi

          echo "Notification queued"
        }
        """,
        else: ""

    send_document_function =
      if has_send_document,
        do: """
        telegram_send_document() {
          local file_path=""
          local caption=""

          while [ $# -gt 0 ]; do
            case "$1" in
              --caption)
                caption="$2"
                shift 2
                ;;
              *)
                if [ -z "$file_path" ]; then
                  file_path="$1"
                fi
                shift
                ;;
            esac
          done

          if [ -z "$file_path" ]; then
            echo "Error: File path is required" >&2
            echo "Usage: invader telegram send-document <file_path> [--caption \\"message\\"]" >&2
            exit 1
          fi

          if [ ! -f "$file_path" ]; then
            echo "Error: File not found: $file_path" >&2
            exit 1
          fi

          # Get filename from path
          local filename
          filename=$(basename "$file_path")

          # Base64 encode the file
          local file_content
          file_content=$(base64 < "$file_path" | tr -d '\\n')

          # Escape filename and caption for JSON
          filename="${filename//\\\\/\\\\\\\\}"
          filename="${filename//\\"/\\\\\\"}"

          local input="{\\"operation\\": \\"send_document\\", \\"filename\\": \\"${filename}\\", \\"file_content\\": \\"${file_content}\\""
          if [ -n "$caption" ]; then
            caption="${caption//\\\\/\\\\\\\\}"
            caption="${caption//\\"/\\\\\\"}"
            input+=", \\"caption\\": \\"${caption}\\""
          fi
          input+="}"

          local result
          result=$(api_call "telegram" "$input")

          local error
          error=$(echo "$result" | jq -r '.error // empty' 2>/dev/null || true)
          if [ -n "$error" ]; then
            local err_message
            err_message=$(echo "$result" | jq -r '.message // empty' 2>/dev/null || true)
            echo "Error: $error" >&2
            [ -n "$err_message" ] && echo "$err_message" >&2
            exit 1
          fi

          echo "Document sent: $filename"
        }
        """,
        else: ""

    """
    # Telegram help
    show_telegram_help() {
      cat <<'HELPEOF'
    Telegram Commands - Human-in-the-loop interaction

    Usage: invader telegram <command> [args...]

    Commands:
    #{commands_help}

    Options for 'ask':
      --timeout <ms>      Timeout in milliseconds (default: 300000 = 5 min)

    Examples:
      invader telegram ask "Should I deploy to production?"
      invader telegram notify "Build completed successfully"
    HELPEOF
    }

    # Telegram command handler
    cmd_telegram() {
      check_config

      if [ $# -eq 0 ]; then
        show_telegram_help
        exit 0
      fi

      case "$1" in
        --help|-h)
          show_telegram_help
          exit 0
          ;;
    #{ask_case}#{notify_case}#{send_document_case}    *)
          echo "Unknown telegram command: $1" >&2
          echo "Run 'invader telegram --help' for available commands." >&2
          exit 1
          ;;
      esac
    }

    #{ask_function}#{notify_function}#{send_document_function}
    """
  end

  defp generate_category_handlers(grouped) do
    grouped
    |> Enum.map(fn {category, scopes} ->
      actions = extract_actions(scopes)
      action_case = generate_action_case(category, actions)
      help_text = generate_category_help_text(category, scopes)

      """
      show_#{category}_help() {
        cat <<'HELPEOF'
      #{help_text}
      HELPEOF
      }

      cmd_gh_#{category}() {
        if [ $# -eq 0 ]; then
          show_#{category}_help
          exit 0
        fi

        case "$1" in
          --help|-h)
            show_#{category}_help
            exit 0
            ;;
      #{action_case}
          *)
            echo "Unknown command: gh #{category} $1" >&2
            echo "Run 'invader gh #{category} --help' for available commands." >&2
            exit 1
            ;;
        esac
      }
      """
    end)
    |> Enum.join("\n")
  end

  defp generate_category_case(grouped) do
    grouped
    |> Enum.map(fn {category, _} ->
      "    #{category})\n      shift\n      cmd_gh_#{category} \"$@\"\n      ;;"
    end)
    |> Enum.join("\n")
  end

  defp generate_action_case(category, actions) do
    actions
    |> Enum.map(fn action ->
      "    #{action})\n      shift\n      run_gh_command \"#{category}\" \"#{action}\" \"$@\"\n      ;;"
    end)
    |> Enum.join("\n")
  end

  defp extract_actions(scopes) do
    scopes
    |> Enum.map(fn {scope, _info} ->
      scope
      |> String.split(":")
      |> List.last()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp generate_main_help_text(grouped, has_telegram) do
    categories = Map.keys(grouped) |> Enum.sort()
    has_github = categories != []

    commands =
      []
      |> then(fn list ->
        if has_github, do: ["  invader gh          GitHub CLI commands" | list], else: list
      end)
      |> then(fn list ->
        if has_telegram,
          do: ["  invader telegram    Telegram commands (human-in-the-loop)" | list],
          else: list
      end)
      |> Enum.reverse()
      |> Enum.join("\n")

    help_hints =
      []
      |> then(fn list ->
        if has_github,
          do: ["Run 'invader gh --help' for available GitHub commands." | list],
          else: list
      end)
      |> then(fn list ->
        if has_telegram,
          do: ["Run 'invader telegram --help' for Telegram commands." | list],
          else: list
      end)
      |> Enum.reverse()
      |> Enum.join("\n")

    if commands == "" do
      """
      Invader CLI

      No commands are available for this mission.
      """
    else
      """
      Invader CLI - Proxy for sprites

      Usage: invader <command> [args...]

      Commands:
      #{commands}

      #{help_hints}
      """
    end
  end

  defp generate_gh_help_text(grouped) do
    categories = Map.keys(grouped) |> Enum.sort()

    if categories == [] do
      """
      GitHub CLI Commands

      No GitHub commands are available for this mission.
      """
    else
      category_list =
        categories
        |> Enum.map(fn cat ->
          desc = category_description(cat)
          "  #{String.pad_trailing(cat, 12)}#{desc}"
        end)
        |> Enum.join("\n")

      """
      GitHub CLI Commands

      Usage: invader gh <command> [args...]

      Available commands:
      #{category_list}

      Run 'invader gh <command> --help' for more information.
      """
    end
  end

  defp generate_category_help_text(category, scopes) do
    action_list =
      scopes
      |> Enum.sort_by(fn {scope, _} -> scope end)
      |> Enum.map(fn {_scope, info} ->
        action = info.command |> String.split() |> Enum.at(3, "unknown")
        "  #{String.pad_trailing(action, 12)}#{info.description}"
      end)
      |> Enum.join("\n")

    examples =
      scopes
      |> Enum.take(2)
      |> Enum.map(fn {_scope, info} -> "  #{info.command}" end)
      |> Enum.join("\n")

    """
    GitHub #{String.capitalize(category)} Commands

    Usage: invader gh #{category} <action> [args...]

    Available actions:
    #{action_list}

    Examples:
    #{examples}
    """
  end

  defp category_description(category) do
    case category do
      "pr" -> "Work with pull requests"
      "issue" -> "Work with issues"
      "repo" -> "Work with repositories"
      _ -> "#{category} commands"
    end
  end
end
