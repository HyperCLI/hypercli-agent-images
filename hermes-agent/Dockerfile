ARG HERMES_BASE_IMAGE=nousresearch/hermes-agent:v2026.8.3@sha256:16788311e2fa3035456bdc1bafb8ec2b1777db64ebf020af9bb7eb73c3712c9e
ARG HYPERCLI_REF=main
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git

FROM ${HERMES_BASE_IMAGE}

ARG HERMES_BASE_IMAGE
ARG HYPERCLI_REF
ARG HYPERCLI_REPO

LABEL org.opencontainers.image.base.name="${HERMES_BASE_IMAGE}"
LABEL org.hypercli.hypercli_ref="${HYPERCLI_REF}"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    ffmpeg \
    poppler-utils \
    lsof \
    python3 \
    python3-dev \
    python3-pip \
    ripgrep \
    build-essential \
    sudo \
    vim \
    xxd \
    nano \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 "${HYPERCLI_REPO}" /opt/hypercli && \
    git -C /opt/hypercli fetch --depth 1 origin "${HYPERCLI_REF}" && \
    git -C /opt/hypercli checkout FETCH_HEAD && \
    git -C /opt/hypercli rev-parse HEAD > /opt/hypercli/.baked-ref && \
    test -n "$(find /opt/hypercli/skills -type f -name SKILL.md -print -quit)" && \
    uv pip install --python /opt/hermes/.venv/bin/python \
      /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    ln -sf /opt/hermes/.venv/bin/hyper /usr/local/bin/hyper && \
    hyper --help >/dev/null

COPY --chmod=0644 config.yaml /opt/hypercli-hermes/config.yaml
COPY --chmod=0755 entrypoint.sh /opt/hypercli-hermes/entrypoint.sh

ENV HERMES_HOME=/opt/data
ENV HERMES_WRITE_SAFE_ROOT=/opt/data
ENV HYPER_WORKSPACES_DIR=/opt/data/workspaces
ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com
ENV HERMES_DEFAULT_MODEL=kimi-k2.6-anthropic
ENV HERMES_MODEL_TRANSPORT=anthropic_messages
ENV API_SERVER_ENABLED=true
ENV API_SERVER_HOST=0.0.0.0
ENV API_SERVER_PORT=8642

EXPOSE 8642

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=6 \
  CMD curl -fsS http://127.0.0.1:8642/health >/dev/null || exit 1

# Keep the wrapper as PID 1 only long enough to seed missing default config,
# then exec the upstream dispatcher so s6-overlay retains its native lifecycle.
ENTRYPOINT ["/opt/hypercli-hermes/entrypoint.sh"]
CMD ["gateway", "run"]
