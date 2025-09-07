# Azure Pipelines Self-Hosted Agent in Docker

Run Azure Pipelines self-hosted agents in Docker containers.

## Quick Start

1. **Prerequisites**
   - VM with Docker Desktop
   - Azure DevOps organization
   - Permission to create agent pools

2. **Setup**
   ```bash
   # Clone and navigate
   git clone <this-repo>
   cd azure-pipelines-agent-docker
   
   # Create environment file
   cp .env.sample .env
   # Edit .env with your values (never commit this file!)
   ```

3. **Configure Environment**
   Edit `.env` with your actual values:
   ```bash
   AZP_URL=https://dev.azure.com/yourorganization
   AZP_TOKEN=your_personal_access_token
   AZP_POOL=Default
   AZP_AGENT_NAME=my-docker-agent
   ```

4. **Run**
   ```bash
   # Option 1: Docker Compose (recommended)
   docker compose up -d
   
   # Option 2: Docker run
   docker build -t azp-agent .
   source .env && docker run -d \
     -e AZP_URL="$AZP_URL" \
     -e AZP_TOKEN="$AZP_TOKEN" \
     -e AZP_POOL="$AZP_POOL" \
     -e AZP_AGENT_NAME="$AZP_AGENT_NAME" \
     --name azure-pipelines-agent \
     azp-agent
   ```

## Security Notes

- **Never commit secrets** - `.env` is gitignored
- **Scope PAT narrowly** - Only Agent Pools (read, manage)
- **Use short-lived tokens** - Rotate PATs regularly
- **Run as non-root** - Container uses unprivileged user
- **No Docker socket** - Agent runs in isolated container

## Maintenance

- **Update agent version**: Change `AZP_AGENT_VERSION` in Dockerfile
- **Graceful shutdown**: `docker compose down` or `docker stop`
- **View logs**: `docker compose logs -f`
- **Clean restart**: `docker compose down && docker compose up -d`

## Enterprise Usage

For production environments:
- Store secrets in managed vaults (Azure Key Vault, etc.)
- Use service principals instead of PATs where possible
- Implement image scanning and signing
- Set up automated rebuilds for security updates
- Use restricted agent pools with appropriate labels

## Troubleshooting

- **Agent won't register**: Check AZP_URL, AZP_TOKEN, and AZP_POOL values
- **Permission denied**: Verify PAT has Agent Pools (read, manage) scope
- **Architecture mismatch**: Uses multi-arch base images, rebuilds automatically detect platform