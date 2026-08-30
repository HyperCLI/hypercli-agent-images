# syntax=docker/dockerfile:1.7

ARG HYPER_ACP_BASE_IMAGE=hyper-acp-base:local
ARG BUZZ_BASE_IMAGE=${HYPER_ACP_BASE_IMAGE}
FROM ${BUZZ_BASE_IMAGE}

ARG KIMI_CODE_VERSION=0.31.0

USER root
COPY --chown=node:node kimi-code/tui.toml /opt/hypercli-buzz/kimi-tui.toml
COPY --chmod=0755 kimi-code/entrypoint.sh /usr/local/bin/hypercli-buzz-kimi-entrypoint
COPY --chmod=0755 kimi-code/runtime-auth.sh /usr/local/bin/hypercli-kimi-auth
RUN export HOME=/root && \
    npm install --global --no-audit --no-fund \
      "@moonshot-ai/kimi-code@${KIMI_CODE_VERSION}" && \
    ln -s hypercli-kimi-auth /usr/local/bin/hypercli-runtime-auth && \
    kimi --version && \
    kimi acp --help >/dev/null && \
    printf '%s\n' kimi-code > /opt/hypercli-buzz/runtime

LABEL org.opencontainers.image.title="HyperCLI Buzz Kimi Code Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz" \
      org.hypercli.coding_runtime="kimi-code" \
      org.hypercli.coding_runtime_version="${KIMI_CODE_VERSION}"

ENV KIMI_CODE_HOME=/home/node/.kimi-code \
    KIMI_DISABLE_TELEMETRY=1 \
    BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/kimi \
    BUZZ_ACP_AGENT_ARGS=acp

USER node
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-kimi-entrypoint"]
CMD ["sleep", "infinity"]
