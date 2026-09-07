# syntax=docker/dockerfile:1.7

ARG RUST_IMAGE=docker.io/library/rust:1.95.0-bookworm@sha256:6258907abe69656e41cd992e0b705cdcfabcbbe3db374f92ed2d47121282d4a1
ARG HYPERCLI_AGENT_BASE_IMAGE=hypercli-agent-base:local
ARG HYPERCLI_CACHE_BUST=local

FROM ${HYPERCLI_AGENT_BASE_IMAGE} AS hypercli-source

FROM ${RUST_IMAGE} AS source-builder

ARG BUZZ_REPO=https://github.com/block/buzz.git
ARG HYPERCLI_CACHE_BUST=local

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    libssl-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY --from=hypercli-source /opt/hypercli /build/hypercli
RUN set -eux; \
    printf '%s\n' "${HYPERCLI_CACHE_BUST}" >/dev/null; \
    BUZZ_REF="$(sed -n 's/^- \{0,1\}Source commit: `\([0-9a-f]\{40\}\)`$/\1/p' /build/hypercli/hyper-acp/plugins/buzz/PROVENANCE.md)"; \
    printf '%s' "${BUZZ_REF}" | grep -Eq '^[0-9a-f]{40}$'; \
    mkdir -p /out; \
    printf '%s\n' "${BUZZ_REF}" > /out/buzz-ref; \
    git init /build/buzz-git; \
    git -C /build/buzz-git remote add origin "${BUZZ_REPO}"; \
    git -C /build/buzz-git fetch --depth 1 origin "${BUZZ_REF}"; \
    test "$(git -C /build/buzz-git rev-parse FETCH_HEAD)" = "${BUZZ_REF}"; \
    git -C /build/buzz-git checkout --detach FETCH_HEAD

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/build/buzz-git/target,sharing=locked \
    set -eux; \
    cargo build \
      --manifest-path /build/buzz-git/Cargo.toml \
      --profile sprig \
      --locked \
      -p sprig; \
    cargo build \
      --manifest-path /build/buzz-git/Cargo.toml \
      --profile sprig \
      --locked \
      -p buzz-sdk \
      --example compute_auth_tag; \
    install -D -m 0755 /build/buzz-git/target/sprig/sprig /out/sprig; \
    install -D -m 0755 \
      /build/buzz-git/target/sprig/examples/compute_auth_tag \
      /out/tools/compute_auth_tag; \
    install -D -m 0644 \
      /build/buzz-git/desktop/src-tauri/src/managed_agents/nest_skill.md \
      /out/nest/.agents/skills/buzz-cli/SKILL.md; \
    strip /out/sprig /out/tools/compute_auth_tag

RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/build/hypercli/target,sharing=locked \
    set -eux; \
    cargo build \
      --manifest-path /build/hypercli/Cargo.toml \
      --release \
      --locked \
      -p hyper-acp \
      -p buzz-acp; \
    install -D -m 0755 /build/hypercli/target/release/hyper-acp /out/hyper-acp; \
    install -D -m 0755 /build/hypercli/target/release/buzz-acp /out/plugins/buzz-acp; \
    strip /out/hyper-acp /out/plugins/buzz-acp

FROM ${HYPERCLI_AGENT_BASE_IMAGE}

ARG HYPERCLI_AGENT_BASE_IMAGE
ARG HYPERCLI_CACHE_BUST

LABEL org.opencontainers.image.source="https://github.com/HyperCLI/hyperclaw-backend" \
      org.opencontainers.image.title="HyperCLI ACP Base" \
      org.opencontainers.image.base.name="${HYPERCLI_AGENT_BASE_IMAGE}" \
      org.hypercli.hypercli_cache_bust="${HYPERCLI_CACHE_BUST}" \
      org.hypercli.coding_runtime="acp-base"

USER root
RUN rm -rf /home/node/.buzz && \
    install -d -m 0755 /opt/hypercli-coding/nest && \
    install -d -m 0700 -o node -g node \
      /home/node/.coding-agent \
      /home/node/shared

COPY --from=source-builder /out/sprig /usr/local/bin/sprig
COPY --from=source-builder /out/nest /opt/hypercli-coding/nest
COPY --from=source-builder /out/hyper-acp /usr/local/bin/hyper-acp
COPY --from=source-builder /out/plugins/buzz-acp /usr/local/lib/hyper-acp/plugins/buzz-acp
COPY --from=source-builder /out/tools/compute_auth_tag /usr/local/lib/hyper-acp/tools/compute_auth_tag
COPY --from=source-builder /out/buzz-ref /opt/hypercli-coding/.buzz-commit
COPY SKILLS.md /opt/hypercli-coding/SKILLS.md
COPY --chmod=0755 init.sh /usr/local/bin/hypercli-coding-init
COPY --chmod=0755 entrypoint.sh /usr/local/bin/hypercli-coding-entrypoint

RUN find /opt/hypercli/skills -mindepth 2 -maxdepth 2 \
      -name SKILL.md -type f -print -quit | grep -q . && \
    ln -s sprig /usr/local/bin/buzz-dev-mcp && \
    ln -s sprig /usr/local/bin/buzz && \
    ln -s /opt/hypercli-coding /opt/hypercli-buzz && \
    ln -s hypercli-coding-init /usr/local/bin/hypercli-buzz-init && \
    ln -s hypercli-coding-entrypoint /usr/local/bin/hypercli-buzz-entrypoint && \
    hyper-acp --help >/dev/null && \
    hyper-acp plugin buzz --help >/dev/null && \
    test -x /usr/local/lib/hyper-acp/tools/compute_auth_tag && \
    buzz --help >/dev/null

ENV CODING_AGENT_STATE_DIR=/home/node/.coding-agent \
    CODING_AGENT_WORKSPACE_DIR=/home/node/.buzz

WORKDIR /home/node
USER node
HEALTHCHECK NONE
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hypercli-coding-entrypoint"]
CMD ["sleep", "infinity"]
