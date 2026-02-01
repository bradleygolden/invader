#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

RELEASE_URL="https://github.com/bradleygolden/invader/releases/latest/download/invader.tar.gz"
VERSION="${1:-latest}"

echo -e "${BLUE}🔄 Invader Updater${NC}"
echo ""

# Ensure we can read from terminal (needed when piped via curl | bash)
if [ -t 0 ]; then
  TTY_IN=/dev/stdin
else
  TTY_IN=/dev/tty
fi

# Check for sprite CLI
if ! command -v sprite &> /dev/null; then
  echo -e "${RED}Error: 'sprite' CLI not found${NC}"
  echo "Install it from: https://sprites.dev"
  exit 1
fi

# Check authentication by listing orgs
echo "Checking authentication..."
ORGS=$(sprite org list 2>&1) || {
  echo -e "${RED}Error: sprite CLI not authenticated${NC}"
  echo "Run: sprite login"
  exit 1
}

# Parse orgs from numbered list format: "  1. org-name (via ...)"
ORG_LIST=($(echo "$ORGS" | grep -E '^\s+[0-9]+\.' | sed 's/^[[:space:]]*[0-9]*\.[[:space:]]*//' | awk '{print $1}'))

if [ ${#ORG_LIST[@]} -eq 0 ]; then
  echo -e "${RED}Error: No organizations found${NC}"
  echo "Run: sprite login"
  exit 1
elif [ ${#ORG_LIST[@]} -eq 1 ]; then
  ORG="${ORG_LIST[0]}"
  echo "Using organization: $ORG"
else
  echo "Available organizations:"
  for i in "${!ORG_LIST[@]}"; do
    echo "  $((i+1)). ${ORG_LIST[$i]}"
  done
  echo ""
  read -p "Select organization [1]: " ORG_NUM < "$TTY_IN"
  ORG_NUM=${ORG_NUM:-1}
  ORG="${ORG_LIST[$((ORG_NUM-1))]}"
fi

# List sprites in org
echo ""
echo "Fetching sprites in $ORG..."
SPRITES_OUTPUT=$(sprite list -o "$ORG" 2>&1) || {
  echo -e "${RED}Error: Could not list sprites${NC}"
  exit 1
}

# Parse sprite names - they appear as "name:" at the start of lines
SPRITE_LIST=($(echo "$SPRITES_OUTPUT" | grep -E '^[a-zA-Z0-9]' | grep ':' | sed 's/:.*//'))

if [ ${#SPRITE_LIST[@]} -eq 0 ]; then
  echo -e "${RED}Error: No sprites found in $ORG${NC}"
  echo "Run the install script first to create a sprite."
  exit 1
elif [ ${#SPRITE_LIST[@]} -eq 1 ]; then
  SPRITE_NAME="${SPRITE_LIST[0]}"
  echo "Using sprite: $SPRITE_NAME"
else
  echo "Available sprites:"
  for i in "${!SPRITE_LIST[@]}"; do
    echo "  $((i+1)). ${SPRITE_LIST[$i]}"
  done
  echo ""
  read -p "Select sprite to update [1]: " SPRITE_NUM < "$TTY_IN"
  SPRITE_NUM=${SPRITE_NUM:-1}
  SPRITE_NAME="${SPRITE_LIST[$((SPRITE_NUM-1))]}"
fi

# Confirm update
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Update Confirmation${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Organization: $ORG"
echo "  Sprite:       $SPRITE_NAME"
echo "  Version:      $VERSION"
echo ""
echo "This will:"
echo "  - Stop the running Invader daemon"
echo "  - Backup the current release"
echo "  - Download and install the new release"
echo "  - Run database migrations"
echo "  - Start the new daemon"
echo ""
echo -e "${GREEN}Your database and configuration will be preserved.${NC}"
echo ""
read -p "Continue with update? [y/N]: " CONFIRM < "$TTY_IN"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Update cancelled."
  exit 0
fi

# Determine download URL
if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="$RELEASE_URL"
else
  DOWNLOAD_URL="https://github.com/bradleygolden/invader/releases/download/${VERSION}/invader.tar.gz"
fi

# Run update on sprite
echo ""
echo "Updating Invader on $SPRITE_NAME..."
sprite exec -o "$ORG" -s "$SPRITE_NAME" -- bash -c "
  set -e

  INVADER_DIR=\"\${HOME}/invader\"
  BACKUP_DIR=\"\${HOME}/invader.backup.\$(date +%s)\"
  DATABASE_FILE=\"\${HOME}/invader.db\"
  ENV_FILE=\"\${HOME}/.env\"

  echo '═══════════════════════════════════════════════════════════════'
  echo '  Invader Update'
  echo '═══════════════════════════════════════════════════════════════'
  echo ''

  # Check current installation exists
  if [ ! -d \"\$INVADER_DIR\" ]; then
    echo 'Error: No existing installation at ~/invader'
    echo 'Run the install script first.'
    exit 1
  fi

  # Verify config exists
  echo 'Checking existing files...'
  if [ -f \"\$DATABASE_FILE\" ]; then
    echo \"  ✓ Database: \$DATABASE_FILE (will be preserved)\"
  else
    echo '  ⚠ Database not found (new installation?)'
  fi

  if [ -f \"\$ENV_FILE\" ]; then
    echo \"  ✓ Config: \$ENV_FILE (will be preserved)\"
  else
    echo '  ✗ Error: Config file ~/.env not found'
    exit 1
  fi

  # Stop the running daemon
  echo ''
  echo 'Stopping Invader daemon...'
  if [ -f \"\$INVADER_DIR/bin/invader\" ]; then
    \"\$INVADER_DIR/bin/invader\" stop 2>/dev/null || true
    sleep 2
  fi

  # Backup current release
  echo \"Backing up current release to: \$BACKUP_DIR\"
  mv \"\$INVADER_DIR\" \"\$BACKUP_DIR\"

  # Download new release
  echo ''
  echo 'Downloading new release...'
  if ! curl -fsSL \"$DOWNLOAD_URL\" -o /tmp/invader.tar.gz; then
    echo 'Error: Failed to download release'
    echo 'Restoring backup...'
    mv \"\$BACKUP_DIR\" \"\$INVADER_DIR\"
    \"\$INVADER_DIR/bin/invader\" daemon
    exit 1
  fi

  # Extract new release
  echo 'Extracting new release...'
  tar -xzf /tmp/invader.tar.gz -C \"\$HOME\"
  rm /tmp/invader.tar.gz

  # Run migrations
  echo ''
  echo 'Running database migrations...'
  set -a && source \"\$ENV_FILE\" && set +a
  \"\$INVADER_DIR/bin/invader\" eval 'for repo <- Application.fetch_env!(:invader, :ecto_repos), do: Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))'

  # Start new daemon
  echo ''
  echo 'Starting new daemon...'
  \"\$INVADER_DIR/bin/invader\" daemon

  # Verify running
  echo 'Waiting for application to start...'
  for i in {1..15}; do
    if \"\$INVADER_DIR/bin/invader\" pid > /dev/null 2>&1; then
      echo ''
      echo '═══════════════════════════════════════════════════════════════'
      echo '  ✅ Update successful!'
      echo '═══════════════════════════════════════════════════════════════'
      echo ''
      echo \"  Database preserved: \$DATABASE_FILE\"
      echo \"  Config preserved:   \$ENV_FILE\"
      echo \"  Release backup:     \$BACKUP_DIR\"
      echo ''
      echo \"  To remove backup: rm -rf \$BACKUP_DIR\"
      exit 0
    fi
    sleep 1
  done

  echo ''
  echo '⚠ Warning: Application may still be starting.'
  echo 'Check logs with: sprite exec -o $ORG -s $SPRITE_NAME -- tail -f invader/tmp/log/erlang.log.1'
" < /dev/null

# Get public URL
echo ""
URL_OUTPUT=$(sprite url -o "$ORG" -s "$SPRITE_NAME" 2>/dev/null || true)
PUBLIC_URL=$(echo "$URL_OUTPUT" | grep -oE 'https://[^ ]+' || true)

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Update complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
if [ -n "$PUBLIC_URL" ]; then
  echo -e "  URL: ${BLUE}${PUBLIC_URL}${NC}"
  echo ""
fi
echo -e "${YELLOW}To view logs:${NC}"
echo "  sprite exec -o $ORG -s $SPRITE_NAME -- tail -f invader/tmp/log/erlang.log.1"
echo ""
echo -e "${YELLOW}To rollback:${NC}"
echo "  sprite exec -o $ORG -s $SPRITE_NAME -- bash -c '"
echo "    ./invader/bin/invader stop"
echo "    rm -rf ~/invader"
echo "    mv ~/invader.backup.* ~/invader"
echo "    ./invader/bin/invader daemon"
echo "  '"
echo ""
