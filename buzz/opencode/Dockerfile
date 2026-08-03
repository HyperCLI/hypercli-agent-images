# syntax=docker/dockerfile:1.7

ARG BUZZ_BASE_IMAGE=hypercli-buzz-base:local
FROM ${BUZZ_BASE_IMAGE}

ARG OPENCODE_VERSION=1.18.9

USER root
COPY --chown=node:node opencode/opencode.json /opt/hypercli-buzz/opencode.json
COPY --chmod=0755 opencode/entrypoint.sh /usr/local/bin/hypercli-buzz-opencode-entrypoint
RUN export HOME=/root && \
    npm install --global --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}" && \
    opencode --version && \
    printf '%s\n' opencode > /opt/hypercli-buzz/runtime

LABEL org.opencontainers.image.title="HyperCLI Buzz OpenCode Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz" \
      org.hypercli.coding_runtime="opencode" \
      org.hypercli.coding_runtime_version="${OPENCODE_VERSION}"

ENV BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/opencode \
    BUZZ_ACP_AGENT_ARGS=acp

USER node
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-opencode-entrypoint"]
CMD ["sleep", "infinity"]
