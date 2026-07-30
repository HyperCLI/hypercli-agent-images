# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=docker.io/library/node:24-bookworm-slim@sha256:6f7b03f7c2c8e2e784dcf9295400527b9b1270fd37b7e9a7285cf83b6951452d
ARG RUST_IMAGE=docker.io/library/rust:1.95.0-bookworm@sha256:6258907abe69656e41cd992e0b705cdcfabcbbe3db374f92ed2d47121282d4a1

ARG BUZZ_REPO=https://github.com/block/buzz.git
ARG BUZZ_COMMIT=6300a6b1d03e32c473c7b6568df663c8927565cf

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

COPY AGENTS.md /expected/AGENTS.md
RUN cmp \
    /expected/AGENTS.md \
    /build/buzz/desktop/src-tauri/src/managed_agents/nest_agents.md

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
      /build/buzz/desktop/src-tauri/src/managed_agents/nest_skill.md \
      /out/nest/.agents/skills/buzz-cli/SKILL.md; \
    strip /out/sprig

FROM ${NODE_IMAGE}

ARG NODE_IMAGE
ARG BUZZ_COMMIT
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git
ARG HYPERCLI_REF

LABEL org.opencontainers.image.source="https://github.com/HyperCLI/hyperclaw-backend" \
      org.opencontainers.image.title="HyperCLI Buzz Agent Base" \
      org.opencontainers.image.base.name="${NODE_IMAGE}" \
      org.hypercli.buzz_commit="${BUZZ_COMMIT}" \
      org.hypercli.coding_runtime="base"

ENV DEBIAN_FRONTEND=noninteractive

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ffmpeg \
    poppler-utils \
    lsof \
    openssh-client \
    procps \
    python3 \
    python3-dev \
    python3-pip \
    build-essential \
    sudo \
    tini \
    vim \
    xxd \
    nano \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    printf '%s' "${HYPERCLI_REF}" | grep -Eq '^[0-9a-f]{40}$'; \
    git init /opt/hypercli; \
    git -C /opt/hypercli remote add origin "${HYPERCLI_REPO}"; \
    git -C /opt/hypercli fetch --depth 1 origin "${HYPERCLI_REF}"; \
    test "$(git -C /opt/hypercli rev-parse FETCH_HEAD)" = "${HYPERCLI_REF}"; \
    git -C /opt/hypercli checkout --detach FETCH_HEAD; \
    git -C /opt/hypercli rev-parse HEAD > /opt/hypercli/.baked-ref; \
    pip3 install --break-system-packages --no-cache-dir \
      /opt/hypercli/sdk \
      "/opt/hypercli/cli[all]"; \
    hyper --help >/dev/null

RUN install -d -m 0755 /opt/hypercli-buzz/nest && \
    install -d -m 0700 -o node -g node \
      /home/node/.coding-agent \
      /home/node/workspaces && \
    printf '%s\n' 'node ALL=(ALL) NOPASSWD:ALL' \
      > /etc/sudoers.d/90-node-nopasswd && \
    chmod 0440 /etc/sudoers.d/90-node-nopasswd

COPY --from=buzz-builder /out/sprig /usr/local/bin/sprig
COPY --from=buzz-builder /out/nest /opt/hypercli-buzz/nest
COPY AGENTS.md /opt/hypercli-buzz/nest/AGENTS.md
COPY --chmod=0755 init.sh /usr/local/bin/hypercli-buzz-init
COPY --chmod=0755 entrypoint.sh /usr/local/bin/hypercli-buzz-entrypoint

RUN ln -s sprig /usr/local/bin/buzz-acp && \
    ln -s sprig /usr/local/bin/buzz-dev-mcp && \
    ln -s sprig /usr/local/bin/buzz && \
    printf '%s\n' "${BUZZ_COMMIT}" > /opt/hypercli-buzz/.buzz-commit && \
    buzz-acp --help >/dev/null && \
    buzz --help >/dev/null

ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com \
    HYPER_API_BASE=https://api.hypercli.com \
    HYPER_AGENTS_WEB_SEARCH_BASE=https://api.agents.hypercli.com/agents/brave \
    HYPER_WORKSPACES_DIR=/home/node/workspaces \
    CODING_AGENT_STATE_DIR=/home/node/.coding-agent \
    CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz \
    BUZZ_ACP_MCP_COMMAND=/usr/local/bin/buzz-dev-mcp

WORKDIR /home/node
USER node
HEALTHCHECK NONE
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-buzz-entrypoint"]
CMD ["sleep", "infinity"]
