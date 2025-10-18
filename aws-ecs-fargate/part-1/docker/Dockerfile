FROM arm64v8/alpine
ENV TARGETARCH="linux-musl-arm64"

RUN apk update && \
  apk upgrade && \
  apk add bash curl gcc git icu-libs jq musl-dev python3-dev libffi-dev openssl-dev cargo make py3-pip zip unzip docker-cli docker-cli-buildx

# Install Azure CLI
RUN pip install --break-system-packages --upgrade pip
RUN pip install --break-system-packages azure-cli

WORKDIR /azp/

COPY ./start.sh ./
RUN chmod +x ./start.sh

RUN adduser -D agent
RUN chown agent ./

# Create shared volume directory and set permissions for agent user
# RUN mkdir -p /shared-volume && chown agent:agent /shared-volume

USER agent
# Another option is to run the agent as root.
# ENV AGENT_ALLOW_RUNASROOT="true"

ENTRYPOINT [ "./start.sh" ]
