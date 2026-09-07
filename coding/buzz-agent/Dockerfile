# syntax=docker/dockerfile:1.7

ARG HYPER_ACP_BASE_IMAGE=hypercli-acp-base:local
FROM ${HYPER_ACP_BASE_IMAGE}

USER root
COPY --chmod=0755 buzz-agent/entrypoint.sh /usr/local/bin/hypercli-coding-buzz-agent-entrypoint
RUN ln -s sprig /usr/local/bin/buzz-agent && \
    test "$(readlink /usr/local/bin/buzz-agent)" = sprig && \
    printf '%s\n' buzz-agent > /opt/hypercli-coding/runtime && \
    ln -s hypercli-coding-buzz-agent-entrypoint /usr/local/bin/hypercli-buzz-agent-entrypoint

LABEL org.opencontainers.image.title="HyperCLI Buzz Native Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.coding_workspace="/home/node/.buzz" \
      org.hypercli.coding_runtime="buzz-agent"

ENV BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/buzz-agent \
    BUZZ_ACP_AGENT_ARGS= \
    BUZZ_ACP_MCP_COMMAND=/usr/local/bin/buzz-dev-mcp

USER node
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-coding-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]
