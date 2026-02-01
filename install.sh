#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

REPO_URL="https://github.com/bradleygolden/invader.git"
BRANCH="main"

echo -e "${BLUE}🚀 Invader Installer${NC}"
echo ""

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
  read -p "Select organization [1]: " ORG_NUM
  ORG_NUM=${ORG_NUM:-1}
  ORG="${ORG_LIST[$((ORG_NUM-1))]}"
fi

# Prompt for sprite name
DEFAULT_NAME="invader-$(openssl rand -hex 4)"
echo ""
read -p "Sprite name [$DEFAULT_NAME]: " SPRITE_NAME
SPRITE_NAME=${SPRITE_NAME:-$DEFAULT_NAME}

echo ""
echo "Creating sprite: $SPRITE_NAME in org: $ORG"
sprite create -o "$ORG" "$SPRITE_NAME"

# Get public URL (extract just the URL from "URL: https://...")
echo "Getting sprite URL..."
URL_OUTPUT=$(sprite url -o "$ORG" -s "$SPRITE_NAME")
PUBLIC_URL=$(echo "$URL_OUTPUT" | grep -oE 'https://[^ ]+')

if [ -z "$PUBLIC_URL" ]; then
  echo -e "${RED}Error: Could not get sprite URL${NC}"
  exit 1
fi

# GitHub OAuth Setup
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GitHub OAuth Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Create a GitHub OAuth App at:"
echo -e "  ${GREEN}https://github.com/settings/applications/new${NC}"
echo ""
echo "Use these values:"
echo -e "  Application name:           ${YELLOW}Invader${NC} (or any name)"
echo -e "  Homepage URL:               ${YELLOW}${PUBLIC_URL}${NC}"
echo -e "  Authorization callback URL: ${YELLOW}${PUBLIC_URL}/auth/user/github/callback${NC}"
echo ""
echo "After creating the app, enter the credentials below:"
echo ""
read -p "GitHub Client ID: " GITHUB_CLIENT_ID
read -sp "GitHub Client Secret: " GITHUB_CLIENT_SECRET
echo ""

# Generate secrets
echo "Generating secrets..."
SECRET_KEY_BASE=$(openssl rand -base64 48)
TOKEN_SIGNING_SECRET=$(openssl rand -base64 48)
CLOAK_KEY=$(openssl rand -base64 32)

# Build and deploy app on sprite
echo ""
echo "Building and deploying Invader (this may take a few minutes)..."
sprite exec -o "$ORG" -s "$SPRITE_NAME" -- bash -c "
  set -e

  echo 'Cloning repository...'
  rm -rf invader-src
  git clone --depth 1 --branch $BRANCH $REPO_URL invader-src
  cd invader-src

  echo 'Installing dependencies...'
  mix local.hex --force
  mix local.rebar --force
  mix deps.get --only prod

  echo 'Compiling application...'
  MIX_ENV=prod mix compile

  echo 'Building assets...'
  MIX_ENV=prod mix assets.deploy

  echo 'Creating release...'
  MIX_ENV=prod mix release --overwrite

  echo 'Installing release...'
  cd ~
  rm -rf invader
  mv invader-src/_build/prod/rel/invader .
  rm -rf invader-src

  # Write environment config
  cat > .env << ENVEOF
SECRET_KEY_BASE=$SECRET_KEY_BASE
TOKEN_SIGNING_SECRET=$TOKEN_SIGNING_SECRET
CLOAK_KEY=$CLOAK_KEY
PHX_HOST=${PUBLIC_URL#https://}
DATABASE_URL=ecto://localhost/invader.db
PHX_SERVER=true
PORT=8080
GITHUB_CLIENT_ID=$GITHUB_CLIENT_ID
GITHUB_CLIENT_SECRET=$GITHUB_CLIENT_SECRET
GITHUB_REDIRECT_URI=${PUBLIC_URL}/auth/user/github/callback
ENVEOF

  # Source env and run migrations
  echo 'Running migrations...'
  set -a && source .env && set +a
  ./invader/bin/invader eval 'for repo <- Application.fetch_env!(:invader, :ecto_repos), do: Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))'

  # Start app in background
  echo 'Starting application...'
  ./invader/bin/invader daemon

  sleep 2
  echo 'Verifying application is running...'
  curl -sf http://localhost:8080/sign-in > /dev/null && echo 'Application started successfully!'
"

# Make URL public only after app is running
echo "Making URL publicly accessible..."
sprite url update -o "$ORG" -s "$SPRITE_NAME" --auth public

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Invader deployed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Public URL: ${BLUE}${PUBLIC_URL}${NC}"
echo ""
echo "Next steps:"
echo "  1. Visit $PUBLIC_URL"
echo "  2. Sign in with GitHub (first user becomes admin)"
echo ""
echo -e "${YELLOW}To manage this sprite:${NC}"
echo "  sprite exec -o $ORG -s $SPRITE_NAME -- <command>"
echo ""
echo -e "${YELLOW}To view logs:${NC}"
echo "  sprite exec -o $ORG -s $SPRITE_NAME -- tail -f invader/tmp/log/erlang.log.1"
