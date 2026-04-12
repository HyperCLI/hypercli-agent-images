# syntax=docker/dockerfile:1.7
FROM ghcr.io/openclaw/openclaw:2026.4.11

ARG HYPERCLI_REF=main
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git

LABEL org.hypercli.hypercli_ref="${HYPERCLI_REF}"
LABEL org.opencontainers.image.base.name="ghcr.io/openclaw/openclaw:2026.4.11"

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
    nano \
    zip \
    unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/hypercli-openclaw /opt/hypercli /app/.openclaw && \
    ln -sfn /app /opt/openclaw && \
    chown -R node:node /app /opt/hypercli-openclaw

RUN git clone --depth 1 "${HYPERCLI_REPO}" /opt/hypercli && \
    git -C /opt/hypercli fetch --depth 1 origin "${HYPERCLI_REF}" && \
    git -C /opt/hypercli checkout FETCH_HEAD && \
    git -C /opt/hypercli rev-parse HEAD > /opt/hypercli/.baked-ref && \
    pip3 install --break-system-packages --no-cache-dir /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    hyper --help >/dev/null

COPY openclaw.json /opt/hypercli-openclaw/openclaw.json
COPY entrypoint.sh /opt/hypercli-openclaw/entrypoint.sh
RUN chmod +x /opt/hypercli-openclaw/entrypoint.sh && \
    chown -R node:node /opt/hypercli-openclaw && \
    openclaw --version

ENV HOME=/app
ENV OPENCLAW_PORT=18789
ENV OPENCLAW_GATEWAY_BIND=lan
ENV OPENCLAW_STATE_DIR=/app/.openclaw
ENV OPENCLAW_CONFIG_PATH=/app/.openclaw/openclaw.json
ENV OPENCLAW_CONFIG_TEMPLATE=/opt/hypercli-openclaw/openclaw.json
ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com

WORKDIR /app
USER node

EXPOSE 18789
ENTRYPOINT ["/opt/hypercli-openclaw/entrypoint.sh"]
