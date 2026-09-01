ARG HERMES_BASE_IMAGE=nousresearch/hermes-agent:v2026.8.3@sha256:16788311e2fa3035456bdc1bafb8ec2b1777db64ebf020af9bb7eb73c3712c9e
ARG HYPERCLI_REF=main
ARG HYPERCLI_SHA
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git

FROM ${HERMES_BASE_IMAGE}

ARG HERMES_BASE_IMAGE
ARG HYPERCLI_REF
ARG HYPERCLI_SHA
ARG HYPERCLI_REPO

LABEL org.opencontainers.image.base.name="${HERMES_BASE_IMAGE}"
LABEL org.hypercli.hypercli_ref="${HYPERCLI_REF}"
LABEL org.hypercli.hypercli_sha="${HYPERCLI_SHA}"

ENV HYPERCLI_REF=${HYPERCLI_REF}
ENV HYPERCLI_SHA=${HYPERCLI_SHA}

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
    && printf '%s\n' 'hermes ALL=(ALL) NOPASSWD:ALL' \
      > /etc/sudoers.d/90-hermes-nopasswd \
    && chmod 0440 /etc/sudoers.d/90-hermes-nopasswd \
    && rm -rf /var/lib/apt/lists/*

ENV COREPACK_HOME=/usr/local/share/corepack
RUN mkdir -p "${COREPACK_HOME}" \
    && npm install --global --force corepack@0.35.0 \
    && corepack install --global pnpm@11.2.2 yarn@1.22.22 \
    && chmod -R a+rX "${COREPACK_HOME}" \
    && corepack --version \
    && pnpm --version \
    && yarn --version

RUN checkout_ref="${HYPERCLI_SHA:-${HYPERCLI_REF}}" && \
    test -n "${checkout_ref}" && \
    git clone --depth 1 "${HYPERCLI_REPO}" /opt/hypercli && \
    git -C /opt/hypercli fetch --depth 1 origin "${checkout_ref}" && \
    git -C /opt/hypercli checkout FETCH_HEAD && \
    { test -z "${HYPERCLI_SHA}" || test "$(git -C /opt/hypercli rev-parse HEAD)" = "${HYPERCLI_SHA}"; } && \
    test -n "$(find /opt/hypercli/skills -type f -name SKILL.md -print -quit)" && \
    uv pip install --python /opt/hermes/.venv/bin/python \
      "mem0ai>=2.0.10,<3" qdrant-client && \
    uv venv --python python3 /opt/hypercli/venv && \
    UV_NO_CONFIG=1 uv pip install --python /opt/hypercli/venv/bin/python \
      /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    ln -sf /opt/hypercli/venv/bin/hyper /usr/local/bin/hyper && \
    hyper --help >/dev/null

COPY --chmod=0644 config.yaml /opt/hypercli-hermes/config.yaml
COPY --chmod=0755 entrypoint.sh /opt/hypercli-hermes/entrypoint.sh

RUN usermod -d /home/hermes hermes \
    && mkdir -p /home/hermes/.hermes /home/hermes/shared \
    && sed -i \
      -e 's#export HOME=/opt/data#export HOME=/home/hermes#g' \
      -e 's#cd /opt/data#cd /home/hermes#g' \
      /opt/hermes/docker/main-wrapper.sh \
    && sed -i \
      -e 's#export HOME=/opt/data#export HOME=/home/hermes#g' \
      /opt/hermes/bin/hermes \
    && chown -R hermes:hermes /home/hermes

COPY --chmod=0600 --chown=hermes:hermes mem0.json /home/hermes/.hermes/mem0.json

ENV HOME=/home/hermes
ENV HERMES_HOME=/home/hermes/.hermes
ENV HERMES_WRITE_SAFE_ROOT=/home/hermes
ENV HYPER_WORKSPACES_DIR=/home/hermes/shared
ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com
ENV API_SERVER_ENABLED=true
ENV API_SERVER_HOST=0.0.0.0
ENV API_SERVER_PORT=8642
ENV HERMES_CRON_ENABLED=
WORKDIR /home/hermes

EXPOSE 8642

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=6 \
  CMD curl -fsS http://127.0.0.1:8642/health >/dev/null || exit 1

# Keep the wrapper as PID 1 only long enough to seed missing default config,
# then exec the upstream dispatcher so s6-overlay retains its native lifecycle.
ENTRYPOINT ["/opt/hypercli-hermes/entrypoint.sh"]
CMD ["gateway", "run"]
