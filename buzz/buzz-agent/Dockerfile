# syntax=docker/dockerfile:1.7

ARG BUZZ_BASE_IMAGE=hypercli-buzz-base:local
FROM ${BUZZ_BASE_IMAGE}

USER root
COPY --chmod=0755 buzz-agent/entrypoint.sh /usr/local/bin/hypercli-buzz-agent-entrypoint
RUN ln -s sprig /usr/local/bin/buzz-agent && \
    test "$(readlink /usr/local/bin/buzz-agent)" = sprig && \
    printf '%s\n' buzz-agent > /opt/hypercli-buzz/runtime

LABEL org.opencontainers.image.title="HyperCLI Buzz Native Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz" \
      org.hypercli.coding_runtime="buzz-agent"

ENV BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/buzz-agent \
    BUZZ_ACP_AGENT_ARGS= \
    BUZZ_ACP_MCP_COMMAND=/usr/local/bin/buzz-dev-mcp

USER node
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]
