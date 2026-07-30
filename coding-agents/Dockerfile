# syntax=docker/dockerfile:1.7

ARG RUST_IMAGE=rust:1.95.0-bookworm
ARG RUNTIME_IMAGE=ghcr.io/hypercli/hypercli-openclaw:prod

ARG BUZZ_REPO=https://github.com/block/buzz.git
ARG BUZZ_COMMIT=6300a6b1d03e32c473c7b6568df663c8927565cf

ARG OPENCODE_VERSION=1.18.9
ARG CODEX_VERSION=0.146.0
ARG CODEX_ACP_VERSION=1.1.7
ARG CLAUDE_CODE_VERSION=2.1.207
ARG CLAUDE_ACP_VERSION=0.59.0
ARG GOOSE_VERSION=1.45.0
ARG GOOSE_AMD64_SHA256=ec5da5f018cf68ea446887d30decf847542035ffcf91536d1d134ed94bb24401
ARG GOOSE_ARM64_SHA256=54afad8e160068cb1769ca2ad3e19e36e8472775e68d7bc89cc90e7779c552d1
ARG KIMI_CODE_VERSION=0.31.0

# The default resolves to the stage below for a standalone build. CI can build
# and push `runtime-base` once, then set this to that image's tested digest in
# the three target jobs so Sprig and HyperCLI are not rebuilt three times.
ARG CODING_AGENT_BASE_IMAGE=runtime-base

FROM ${RUST_IMAGE} AS buzz-builder

ARG BUZZ_REPO
ARG BUZZ_COMMIT

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    libssl-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN set -eux; \
    printf '%s' "${BUZZ_COMMIT}" | grep -Eq '^[0-9a-f]{40}$'; \
    git init buzz; \
    git -C buzz remote add origin "${BUZZ_REPO}"; \
    git -C buzz fetch --depth 1 origin "${BUZZ_COMMIT}"; \
    test "$(git -C buzz rev-parse FETCH_HEAD)" = "${BUZZ_COMMIT}"; \
    git -C buzz checkout --detach FETCH_HEAD

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/build/buzz/target,sharing=locked \
    set -eux; \
    cargo build \
      --manifest-path /build/buzz/Cargo.toml \
      --profile sprig \
      --locked \
      -p sprig; \
    install -D -m 0755 /build/buzz/target/sprig/sprig /out/sprig; \
    install -D -m 0644 \
      /build/buzz/desktop/src-tauri/src/managed_agents/nest_agents.md \
      /out/buzz-nest/AGENTS.md; \
    install -D -m 0644 \
      /build/buzz/desktop/src-tauri/src/managed_agents/nest_skill.md \
      /out/buzz-nest/.agents/skills/buzz-cli/SKILL.md; \
    strip /out/sprig

FROM debian:bookworm-slim AS goose-fetch

ARG TARGETARCH
ARG GOOSE_VERSION
ARG GOOSE_AMD64_SHA256
ARG GOOSE_ARM64_SHA256

RUN apt-get update && apt-get install -y --no-install-recommends \
    bzip2 \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) goose_arch=x86_64; goose_sha256="${GOOSE_AMD64_SHA256}" ;; \
      arm64) goose_arch=aarch64; goose_sha256="${GOOSE_ARM64_SHA256}" ;; \
      *) echo "unsupported Goose target architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    archive="/tmp/goose-${goose_arch}-unknown-linux-gnu.tar.bz2"; \
    curl --fail --location --silent --show-error \
      "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-${goose_arch}-unknown-linux-gnu.tar.bz2" \
      --output "${archive}"; \
    printf '%s  %s\n' "${goose_sha256}" "${archive}" | sha256sum --check --strict; \
    mkdir -p /out; \
    tar -xjf "${archive}" -C /out; \
    test -x /out/goose; \
    /out/goose --version

FROM ${RUNTIME_IMAGE} AS runtime-base

ARG BUZZ_COMMIT
ARG RUNTIME_IMAGE

LABEL org.opencontainers.image.source="https://github.com/HyperCLI/hyperclaw-backend" \
      org.opencontainers.image.title="HyperCLI Coding Agent Base" \
      org.opencontainers.image.base.name="${RUNTIME_IMAGE}" \
      org.hypercli.buzz_commit="${BUZZ_COMMIT}" \
      org.hypercli.coding_runtime="base"

ENV DEBIAN_FRONTEND=noninteractive

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN rm -rf \
      /app \
      /opt/hypercli-openclaw \
      /home/node/.openclaw \
    && rm -f /usr/local/bin/openclaw \
    && mkdir -p \
      /opt/hypercli-coding-agent \
      /home/node/.coding-agent \
      /home/node/workspaces \
    && chown -R node:node \
      /opt/hypercli-coding-agent \
      /home/node \
    && printf '%s\n' 'node ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-node-nopasswd \
    && chmod 0440 /etc/sudoers.d/90-node-nopasswd

COPY --from=buzz-builder /out/sprig /usr/local/bin/sprig
COPY --from=buzz-builder /out/buzz-nest /opt/hypercli-coding-agent/buzz-nest
COPY --chmod=0755 entrypoint.sh /usr/local/bin/hypercli-coding-agent-entrypoint
COPY --chmod=0755 buzz-entrypoint.sh /usr/local/bin/hypercli-buzz-agent-entrypoint
RUN ln -s sprig /usr/local/bin/buzz-acp \
    && ln -s sprig /usr/local/bin/buzz-dev-mcp \
    && ln -s sprig /usr/local/bin/buzz \
    && printf '%s\n' "${BUZZ_COMMIT}" > /opt/hypercli-coding-agent/.buzz-commit \
    && buzz-acp --help >/dev/null \
    && buzz --help >/dev/null

ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com \
    HYPER_API_BASE=https://api.hypercli.com \
    HYPER_AGENTS_WEB_SEARCH_BASE=https://api.agents.hypercli.com/agents/brave \
    HYPER_WORKSPACES_DIR=/home/node/workspaces \
    CODING_AGENT_STATE_DIR=/home/node/.coding-agent \
    CODING_AGENT_WORKSPACE_DIR=/home/node \
    OPENCLAW_PORT= \
    OPENCLAW_GATEWAY_BIND= \
    OPENCLAW_STATE_DIR= \
    OPENCLAW_CONFIG_PATH= \
    OPENCLAW_CONFIG_TEMPLATE= \
    OPENCLAW_BUNDLED_PLUGINS_DIR= \
    OPENCLAW_INSTALL_PLUGINS= \
    OPENCLAW_DESKTOP_ENABLED= \
    OPENCLAW_DESKTOP_PORT= \
    BUZZ_ACP_MCP_COMMAND=/usr/local/bin/buzz-dev-mcp

WORKDIR /home/node
USER node
HEALTHCHECK NONE
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-coding-agent-entrypoint"]
CMD ["sleep", "infinity"]

FROM ${CODING_AGENT_BASE_IMAGE} AS opencode

ARG OPENCODE_VERSION
USER root
COPY --chown=node:node opencode.json /opt/hypercli-coding-agent/opencode.json
RUN npm install --global --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}" \
    && opencode --version \
    && printf '%s\n' opencode > /opt/hypercli-coding-agent/runtime
LABEL org.hypercli.coding_runtime="opencode" \
      org.hypercli.coding_runtime_version="${OPENCODE_VERSION}"
ENV BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/opencode \
    BUZZ_ACP_AGENT_ARGS=acp
USER node

FROM ${CODING_AGENT_BASE_IMAGE} AS codex

ARG CODEX_VERSION
ARG CODEX_ACP_VERSION
USER root
RUN npm install --global --no-audit --no-fund \
      "@openai/codex@${CODEX_VERSION}" \
      "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" \
    && codex --version \
    && codex-acp --version \
    && printf '%s\n' codex > /opt/hypercli-coding-agent/runtime
LABEL org.hypercli.coding_runtime="codex" \
      org.hypercli.coding_runtime_version="${CODEX_VERSION}" \
      org.hypercli.acp_adapter_version="${CODEX_ACP_VERSION}"
ENV BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/codex-acp \
    BUZZ_ACP_AGENT_ARGS=
USER node

FROM ${CODING_AGENT_BASE_IMAGE} AS claude-code

ARG CLAUDE_CODE_VERSION
ARG CLAUDE_ACP_VERSION
USER root
RUN npm install --global --no-audit --no-fund \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "@agentclientprotocol/claude-agent-acp@${CLAUDE_ACP_VERSION}" \
    && claude --version \
    && claude-agent-acp --version \
    && printf '%s\n' claude-code > /opt/hypercli-coding-agent/runtime
LABEL org.hypercli.coding_runtime="claude-code" \
      org.hypercli.coding_runtime_version="${CLAUDE_CODE_VERSION}" \
      org.hypercli.acp_adapter_version="${CLAUDE_ACP_VERSION}"
ENV BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/claude-agent-acp \
    BUZZ_ACP_AGENT_ARGS=
USER node

FROM ${CODING_AGENT_BASE_IMAGE} AS goose

ARG GOOSE_VERSION
USER root
COPY --from=goose-fetch /out/goose /usr/local/bin/goose
COPY --chown=node:node goose-config.yaml /opt/hypercli-coding-agent/goose-config.yaml
COPY --chown=node:node goose-provider.json /opt/hypercli-coding-agent/goose-provider.json
RUN goose --version \
    && goose acp --help >/dev/null \
    && printf '%s\n' goose > /opt/hypercli-coding-agent/runtime
LABEL org.hypercli.coding_runtime="goose" \
      org.hypercli.coding_runtime_version="${GOOSE_VERSION}"
ENV GOOSE_PATH_ROOT=/home/node/.goose \
    GOOSE_DISABLE_KEYRING=1 \
    GOOSE_TELEMETRY_ENABLED=false \
    BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/goose \
    BUZZ_ACP_AGENT_ARGS=acp
USER node

FROM ${CODING_AGENT_BASE_IMAGE} AS kimi-code

ARG KIMI_CODE_VERSION
USER root
COPY --chown=node:node kimi-tui.toml /opt/hypercli-coding-agent/kimi-tui.toml
RUN npm install --global --no-audit --no-fund "@moonshot-ai/kimi-code@${KIMI_CODE_VERSION}" \
    && kimi --version \
    && kimi acp --help >/dev/null \
    && printf '%s\n' kimi-code > /opt/hypercli-coding-agent/runtime
LABEL org.hypercli.coding_runtime="kimi-code" \
      org.hypercli.coding_runtime_version="${KIMI_CODE_VERSION}"
ENV KIMI_CODE_HOME=/home/node/.kimi-code \
    KIMI_DISABLE_TELEMETRY=1 \
    BUZZ_ACP_AGENT_COMMAND=/usr/local/bin/kimi \
    BUZZ_ACP_AGENT_ARGS=acp
USER node

# Buzz-specialized stages preserve the generic runtime images above for direct
# shell/API use while giving hosted Buzz ACP launches the stock ~/.buzz nest.
# Keep WORKDIR inherited as /home/node: the Buzz wrapper creates and enters the
# nest after Lagoon has restored the mounted persistent home.
FROM opencode AS buzz-opencode
LABEL org.opencontainers.image.title="HyperCLI Buzz OpenCode Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz"
ENV CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz \
    HYPERCLI_BUZZ_RUNTIME=opencode
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]

FROM codex AS buzz-codex
LABEL org.opencontainers.image.title="HyperCLI Buzz Codex Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz"
ENV CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz \
    HYPERCLI_BUZZ_RUNTIME=codex
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]

FROM claude-code AS buzz-claude-code
LABEL org.opencontainers.image.title="HyperCLI Buzz Claude Code Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz"
ENV CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz \
    HYPERCLI_BUZZ_RUNTIME=claude-code
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]

FROM goose AS buzz-goose
LABEL org.opencontainers.image.title="HyperCLI Buzz Goose Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz"
ENV CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz \
    HYPERCLI_BUZZ_RUNTIME=goose
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]

FROM kimi-code AS buzz-kimi-code
LABEL org.opencontainers.image.title="HyperCLI Buzz Kimi Code Agent" \
      org.hypercli.buzz_runtime="true" \
      org.hypercli.buzz_workspace="/home/node/.buzz"
ENV CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz \
    HYPERCLI_BUZZ_RUNTIME=kimi-code
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-agent-entrypoint"]
CMD ["sleep", "infinity"]
