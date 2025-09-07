#!/bin/bash
set -e

# Azure Pipelines Agent Entrypoint Script
# Handles agent download, configuration, and graceful shutdown

# Required environment variables check
if [ -z "${AZP_URL}" ]; then
  echo "Error: AZP_URL environment variable is required"
  echo "Example: https://dev.azure.com/yourorganization"
  exit 1
fi

if [ -z "${AZP_TOKEN}" ]; then
  echo "Error: AZP_TOKEN environment variable is required"
  echo "This should be a Personal Access Token with Agent Pools (read, manage) scope"
  exit 1
fi

if [ -z "${AZP_POOL}" ]; then
  echo "Error: AZP_POOL environment variable is required"
  echo "Example: Default or MyCustomPool"
  exit 1
fi

# Set defaults for optional variables - following Microsoft patterns
# Use container hostname directly - Docker Compose provides unique hostnames when scaling
AZP_AGENT_NAME="${AZP_AGENT_NAME:-$(hostname)}"
AZP_WORK="${AZP_WORK:-/home/azp/_work}"

echo "Starting Azure Pipelines Agent..."
echo "Organization URL: ${AZP_URL}"
echo "Agent Pool: ${AZP_POOL}"
echo "Agent Name: ${AZP_AGENT_NAME}"
echo "Work Directory: ${AZP_WORK}"

# Download the agent if not already present
if [ ! -d "/home/azp/agent" ]; then
  echo "Downloading Azure Pipelines Agent v${AZP_AGENT_VERSION}..."
  
  # Determine architecture for Azure DevOps API
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      AGENT_ARCH="linux-x64"
      ;;
    aarch64|arm64)
      AGENT_ARCH="linux-arm64"
      ;;
    *)
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
  
  # Get the latest agent download URL from Azure DevOps API (Microsoft's current recommendation)
  echo "Fetching latest agent download URL from Azure DevOps API..."
  AZP_AGENT_PACKAGES=$(curl -LsS \
    -u user:${AZP_TOKEN} \
    -H "Accept:application/json" \
    "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${AGENT_ARCH}&\$top=1")
  
  if [ ! $? -eq 0 ]; then
    echo "Failed to fetch agent package information from Azure DevOps API"
    exit 1
  fi
  
  AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")
  
  if [ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" ] || [ "${AZP_AGENT_PACKAGE_LATEST_URL}" = "null" ]; then
    echo "Failed to parse agent download URL from API response"
    exit 1
  fi
  
  echo "Downloading agent from: ${AZP_AGENT_PACKAGE_LATEST_URL}"
  curl -LsS -o agent.tar.gz "${AZP_AGENT_PACKAGE_LATEST_URL}"
  
  if [ ! $? -eq 0 ]; then
    echo "Failed to download agent package"
    exit 1
  fi
  
  mkdir -p agent
  tar -xf agent.tar.gz -C agent
  rm agent.tar.gz
  
  echo "Agent downloaded and extracted successfully"
fi

cd agent

# Cleanup function for graceful shutdown
cleanup() {
  echo "Received shutdown signal, cleaning up..."
  
  if [ -e ".agent" ]; then
    echo "Removing agent from pool..."
    ./config.sh remove --unattended --auth pat --token "${AZP_TOKEN}"
    echo "Agent removed successfully"
  fi
  
  exit 0
}

# Set up signal handling for graceful shutdown
trap cleanup SIGTERM SIGINT

# Configure the agent - following Microsoft's recommended parameters
echo "Configuring agent..."
./config.sh \
  --unattended \
  --url "${AZP_URL}" \
  --auth pat \
  --token "${AZP_TOKEN}" \
  --pool "${AZP_POOL}" \
  --agent "${AZP_AGENT_NAME}" \
  --work "${AZP_WORK}" \
  --replace \
  --acceptTeeEula

if [ ! $? -eq 0 ]; then
  echo "Agent configuration failed"
  exit 1
fi

echo "Agent configured successfully"

# Start the agent
echo "Starting agent listener..."
./run.sh &

# Wait for the agent process and handle signals
wait $!