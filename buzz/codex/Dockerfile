# syntax=docker/dockerfile:1.7

ARG BUZZ_BASE_IMAGE=hypercli-buzz-base:local
FROM ${BUZZ_BASE_IMAGE}

ARG CODEX_VERSION=0.146.0
ARG CODEX_ACP_VERSION=1.1.7

USER root
RUN export HOME=/root && \
    npm install --global --no-audit --no-fund \
      "@openai/codex@${CODEX_VERSION}" \
      "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" && \
    codex --version && \
    codex-acp --version && \
    printf '%s\n' codex > /opt/hypercli-buzz/runtime

LABEL org.opencontainers.image.title="HyperCLI Buzz Codex Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz" \
      org.hypercli.coding_runtime="codex" \
      org.hypercli.coding_runtime_version="${CODEX_VERSION}" \
      org.hypercli.acp_adapter_version="${CODEX_ACP_VERSION}"

ENV NO_BROWSER=1 \
    BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/codex-acp \
    BUZZ_ACP_AGENT_ARGS=

USER node
