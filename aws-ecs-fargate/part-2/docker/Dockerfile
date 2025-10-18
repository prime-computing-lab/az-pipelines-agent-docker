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

RUN adduser -D agent
RUN chown agent ./

# Create shared volume directory for EBS volume
# This directory will be mounted to an EBS volume in ECS Fargate
RUN mkdir -p /shared-volume

# AWS requirement: Containers must run as root to write to EBS volumes
# See: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ebs-volumes.html
ENV AGENT_ALLOW_RUNASROOT="true"

ENTRYPOINT [ "./start.sh" ]
