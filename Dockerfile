# Azure Pipelines Self-Hosted Agent in Docker
# Supports both AMD64 and ARM64 architectures

FROM ubuntu:24.04

# Build argument for agent version - allows easy updates
ARG AZP_AGENT_VERSION=4.260.0

# Install required packages following Microsoft recommendations
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    iputils-ping \
    libcurl4 \
    libicu74 \
    libunwind8 \
    netcat-openbsd \
    libssl3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash azp

# Set working directory
WORKDIR /home/azp

# Copy entrypoint script
COPY start.sh /home/azp/start.sh
RUN chmod +x /home/azp/start.sh

# Switch to non-root user
USER azp

# Set environment variables with secure defaults
ENV AZP_AGENT_VERSION=${AZP_AGENT_VERSION}
ENV AZP_WORK="/home/azp/_work"

# Create work directory
RUN mkdir -p ${AZP_WORK}

# Expose agent version for reference
LABEL azp.agent.version=${AZP_AGENT_VERSION}
LABEL maintainer="DevOps Team"

# Health check to ensure agent is responsive
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "Agent.Listener" > /dev/null || exit 1

ENTRYPOINT ["/home/azp/start.sh"]