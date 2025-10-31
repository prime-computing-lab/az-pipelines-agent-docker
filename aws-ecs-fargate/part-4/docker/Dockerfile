FROM arm64v8/alpine
ENV TARGETARCH="linux-musl-arm64"

RUN apk update && \
  apk upgrade && \
  apk add bash curl gcc git icu-libs jq musl-dev python3-dev libffi-dev openssl-dev cargo make py3-pip zip unzip

# Install Azure CLI
RUN pip install --break-system-packages azure-cli

WORKDIR /azp/

COPY ./start.sh ./
RUN chmod +x ./start.sh

# Create shared storage directory for bind mount
# This directory will be mounted using bind mount in ECS Fargate
# Note: Bind mounts are tied to the lifecycle of the container
RUN mkdir -p /shared-storage

# Create non-root user and set ownership
RUN adduser -D agent
RUN chown agent ./
RUN chown agent /shared-storage

USER agent
# Another option is to run the agent as root.
# ENV AGENT_ALLOW_RUNASROOT="true"

ENTRYPOINT [ "./start.sh" ]
