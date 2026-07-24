ARG HYPERCLI_REF=main
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git
ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:2026.7.1

FROM ${OPENCLAW_BASE_IMAGE}

ARG HYPERCLI_REF
ARG HYPERCLI_REPO
ARG OPENCLAW_BASE_IMAGE

LABEL org.hypercli.hypercli_ref="${HYPERCLI_REF}"
LABEL org.opencontainers.image.base.name="${OPENCLAW_BASE_IMAGE}"

ENV DEBIAN_FRONTEND=noninteractive

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ffmpeg \
    poppler-utils \
    lsof \
    python3 \
    python3-dev \
    python3-pip \
    build-essential \
    sudo \
    vim \
    xxd \
    nano \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/hypercli-openclaw /opt/hypercli /home/node/.openclaw && \
    chown -R node:node /home/node /opt/hypercli-openclaw

RUN git clone --depth 1 "${HYPERCLI_REPO}" /opt/hypercli && \
    git -C /opt/hypercli fetch --depth 1 origin "${HYPERCLI_REF}" && \
    git -C /opt/hypercli checkout FETCH_HEAD && \
    git -C /opt/hypercli rev-parse HEAD > /opt/hypercli/.baked-ref && \
    pip3 install --break-system-packages --no-cache-dir /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    hyper --help >/dev/null

RUN set -eux; \
    openclaw_version="$(node -e 'console.log(require("/app/package.json").version)')"; \
    tmp_dir="$(mktemp -d)"; \
    cd "${tmp_dir}"; \
    npm init -y >/dev/null; \
    npm install --omit=dev --ignore-scripts --no-audit --no-fund --legacy-peer-deps \
      "@openclaw/brave-plugin@${openclaw_version}" \
      "@openclaw/slack@${openclaw_version}" \
      "@openclaw/whatsapp@${openclaw_version}"; \
    rm -rf /app/dist-runtime/extensions/brave /app/dist-runtime/extensions/slack /app/dist-runtime/extensions/whatsapp; \
    mkdir -p /app/dist-runtime/extensions; \
    cp -a node_modules/@openclaw/brave-plugin /app/dist-runtime/extensions/brave; \
    cp -a node_modules/@openclaw/slack /app/dist-runtime/extensions/slack; \
    cp -a node_modules/@openclaw/whatsapp /app/dist-runtime/extensions/whatsapp; \
    chown -R node:node /app/dist-runtime/extensions/brave /app/dist-runtime/extensions/slack /app/dist-runtime/extensions/whatsapp; \
    rm -rf "${tmp_dir}"

COPY openclaw.json /opt/hypercli-openclaw/openclaw.json
COPY entrypoint.sh /opt/hypercli-openclaw/entrypoint.sh
RUN chmod +x /opt/hypercli-openclaw/entrypoint.sh && \
    chown -R node:node /opt/hypercli-openclaw && \
    openclaw --version

ENV OPENCLAW_PORT=18789
ENV OPENCLAW_GATEWAY_BIND=lan
ENV OPENCLAW_STATE_DIR=/home/node/.openclaw
ENV OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json
ENV OPENCLAW_CONFIG_TEMPLATE=/opt/hypercli-openclaw/openclaw.json
ENV OPENCLAW_BUNDLED_PLUGINS_DIR=/app/dist-runtime/extensions
ENV OPENCLAW_INSTALL_PLUGINS=
ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com
ENV HYPER_AGENTS_WEB_SEARCH_BASE=https://api.agents.hypercli.com/agents/brave
ENV OPENCLAW_DESKTOP_ENABLED=0
ENV OPENCLAW_DESKTOP_PORT=3000
ENV OPENCLAW_MEMORY_SEARCH_ENABLED=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_ON_SESSION_START=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_ON_SEARCH=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_WATCH=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_WATCH_DEBOUNCE_MS=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_INTERVAL_MINUTES=
ENV DISPLAY=:99

WORKDIR /app
USER node

EXPOSE 18789
ENTRYPOINT ["/opt/hypercli-openclaw/entrypoint.sh"]
