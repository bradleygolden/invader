# Invader

Ralph Loop Command Center - A web interface for managing autonomous Claude Code agents.

## Quick Install

Deploy to a [Sprite](https://sprites.dev) with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/bradleygolden/invader/main/install.sh | bash
```

### Prerequisites

- [Sprite CLI](https://sprites.dev) installed and authenticated (`sprite login`)
- GitHub account (for OAuth authentication)

### What the installer does

1. Creates a new sprite in your organization
2. Guides you through GitHub OAuth App setup
3. Deploys Invader with all secrets configured
4. Makes the URL publicly accessible

The first user to sign in with the setup token becomes the admin.

## Updating

Update an existing Invader deployment:

```bash
curl -fsSL https://raw.githubusercontent.com/bradleygolden/invader/main/update.sh | bash
```

This preserves your database and configuration while updating the application.

To update to a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/bradleygolden/invader/main/update.sh | bash -s -- v0.4.12
```

## Local Development

```bash
# Install dependencies and generate secrets
mix setup
```

This automatically generates required secrets (`CLOAK_KEY`, `TOKEN_SIGNING_SECRET`, `ADMIN_SETUP_TOKEN`) in `.env`.

### GitHub OAuth Setup

1. Create an OAuth App at https://github.com/settings/applications/new
2. Set **Homepage URL** to: `http://localhost:4000`
3. Set **Callback URL** to: `http://localhost:4000/auth/user/github/callback`
4. Add credentials to `.env`:
   ```
   GITHUB_CLIENT_ID=your-client-id
   GITHUB_CLIENT_SECRET=your-client-secret
   ```

### Run the server

```bash
# Source environment and start
source .env && mix phx.server
```

Visit [localhost:4000](http://localhost:4000). Enter the `ADMIN_SETUP_TOKEN` from your `.env` file, then sign in with GitHub.

## License

MIT
