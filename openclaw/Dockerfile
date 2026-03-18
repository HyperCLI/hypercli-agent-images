# syntax=docker/dockerfile:1.7
FROM node:24-bookworm

ARG OPENCLAW_NPM_TAG=latest
ARG HYPERCLI_REF=main
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git

ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV PATH=/opt/npm-global/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ffmpeg \
    python3 \
    python3-dev \
    python3-pip \
    build-essential \
    xvfb \
    x11vnc \
    openbox \
    novnc \
    websockify \
    xauth \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -l ubuntu -d /home/ubuntu -m node && \
    groupmod -n ubuntu node && \
    mkdir -p /opt/hypercli-openclaw/skills /opt/hypercli /opt/openclaw /opt/npm-global /home/ubuntu/.openclaw && \
    chown -R ubuntu:ubuntu /home/ubuntu /opt/hypercli-openclaw /opt/npm-global

RUN git clone --depth 1 --branch "${HYPERCLI_REF}" "${HYPERCLI_REPO}" /opt/hypercli && \
    pip3 install --break-system-packages --no-cache-dir /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    hyper --help >/dev/null && \
    cp -r /opt/hypercli/skills/hypercli /opt/hypercli-openclaw/skills/ && \
    cp -r /opt/hypercli/skills/stt /opt/hypercli-openclaw/skills/ && \
    cp -r /opt/hypercli/skills/voice /opt/hypercli-openclaw/skills/

RUN npm install -g "openclaw@${OPENCLAW_NPM_TAG}" && \
    cp -a /opt/npm-global/lib/node_modules/openclaw/. /opt/openclaw/ && \
    ln -sf /opt/npm-global/bin/openclaw /usr/local/bin/openclaw && \
    npm cache clean --force && \
    openclaw --version

COPY openclaw.json /opt/hypercli-openclaw/openclaw.json
COPY entrypoint.sh /opt/hypercli-openclaw/entrypoint.sh
RUN chmod +x /opt/hypercli-openclaw/entrypoint.sh

ENV HOME=/home/ubuntu
ENV DISPLAY=:99
ENV OPENCLAW_PORT=18789
ENV OPENCLAW_GATEWAY_BIND=lan
ENV OPENCLAW_STATE_DIR=/home/ubuntu/.openclaw
ENV OPENCLAW_CONFIG_PATH=/home/ubuntu/.openclaw/openclaw.json
ENV OPENCLAW_CONFIG_TEMPLATE=/opt/hypercli-openclaw/openclaw.json
ENV HYPERCLAW_API_BASE=https://api.agents.hypercli.com

WORKDIR /home/ubuntu
USER ubuntu

EXPOSE 3000 18789
ENTRYPOINT ["/opt/hypercli-openclaw/entrypoint.sh"]
