# Azure Pipelines Docker Agent with Persistent Storage

A Docker-based setup for running Azure Pipelines agents with persistent storage capabilities. Perfect for scenarios where you need build artifacts to persist across different pipeline stages and agents.

## What's This For?

Ever had a pipeline where one agent builds your app and another needs to deploy it? This setup lets you run multiple Azure Pipelines agents that can share data through persistent storage. No more losing build artifacts between stages!

## Quick Start

1. Copy `.env.example` to `.env` and fill in your Azure DevOps details:
   ```bash
   AZP_URL=https://dev.azure.com/your-org
   AZP_TOKEN=your-personal-access-token
   AZP_POOL=your-agent-pool
   ```

2. Start the agents:
   ```bash
   docker-compose up -d
   ```

3. Check they're running:
   ```bash
   docker-compose ps
   ```

## What You Get

- **Two agents**: `azp-agent-1` and `azp-agent-2` ready to handle your pipelines
- **Persistent storage**: Agents can share files through mounted volumes
- **Auto-restart**: Agents restart automatically if they crash
- **ARM64 support**: Built for Apple Silicon and ARM-based systems
- **Azure CLI included**: Ready for Azure deployments

## Example Pipelines

The repo includes sample pipeline files showing:
- `pipeline-persistent-storage.yml`: How to build on one agent and deploy from another using shared storage
- `pipeline-default-container-storage.yml`: Standard pipeline without persistent storage

## Environment Variables

- `AZP_URL`: Your Azure DevOps organization URL
- `AZP_TOKEN`: Personal access token with agent pool permissions
- `AZP_POOL`: Agent pool name (defaults to "Default")
- `AZP_AGENT_NAME`: Gets set automatically for each container

## Persistent Storage Options

Check out the different Docker Compose files:
- `docker-compose.yml`: Basic setup
- `docker-compose-with-volume.yml`: Adds persistent volume mounting
- `docker-compose-with-volume-broken.yml`: Example of what not to do

## Troubleshooting

**Agents not showing up?** Check your token permissions and pool configuration.

**Build artifacts disappearing?** Make sure you're using the volume-mounted version and saving to `/shared-volume/artifacts`.

**Permission issues?** The agents run as a non-root user for security.

## Security Note

Keep your `.env` file out of version control - it contains your access token!