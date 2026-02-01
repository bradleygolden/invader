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

The first user to sign in becomes the admin.

## Local Development

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

## License

MIT
