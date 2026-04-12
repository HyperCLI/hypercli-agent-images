# syntax=docker/dockerfile:1.7
FROM node:24-bookworm

ARG OPENCLAW_NPM_TAG=2026.4.11
ARG HYPERCLI_REF=main
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git

LABEL org.hypercli.hypercli_ref="${HYPERCLI_REF}"

ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV PATH=/opt/npm-global/bin:${PATH}

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

RUN usermod -l ubuntu -d /home/ubuntu -m node && \
    groupmod -n ubuntu node && \
    mkdir -p /opt/hypercli-openclaw /opt/hypercli /opt/openclaw /opt/npm-global /home/ubuntu/.openclaw && \
    chown -R ubuntu:ubuntu /home/ubuntu /opt/hypercli-openclaw /opt/npm-global && \
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

RUN git clone --depth 1 "${HYPERCLI_REPO}" /opt/hypercli && \
    git -C /opt/hypercli fetch --depth 1 origin "${HYPERCLI_REF}" && \
    git -C /opt/hypercli checkout FETCH_HEAD && \
    git -C /opt/hypercli rev-parse HEAD > /opt/hypercli/.baked-ref && \
    pip3 install --break-system-packages --no-cache-dir /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    hyper --help >/dev/null

RUN npm install -g "openclaw@${OPENCLAW_NPM_TAG}" && \
    find /opt/npm-global/lib/node_modules/openclaw -type f -path '*/skills/*' -name '*.sh' -exec chmod 755 {} + && \
    cp -a /opt/npm-global/lib/node_modules/openclaw/. /opt/openclaw/ && \
    ln -sf /opt/npm-global/bin/openclaw /usr/local/bin/openclaw-real && \
    npm cache clean --force && \
    /usr/local/bin/openclaw-real --version

COPY openclaw.json /opt/hypercli-openclaw/openclaw.json
COPY entrypoint.sh /opt/hypercli-openclaw/entrypoint.sh
RUN chmod +x /opt/hypercli-openclaw/entrypoint.sh && \
    ln -sf /opt/npm-global/bin/openclaw /usr/local/bin/openclaw

ENV HOME=/home/ubuntu
ENV OPENCLAW_PORT=18789
ENV OPENCLAW_GATEWAY_BIND=lan
ENV OPENCLAW_STATE_DIR=/home/ubuntu/.openclaw
ENV OPENCLAW_CONFIG_PATH=/home/ubuntu/.openclaw/openclaw.json
ENV OPENCLAW_CONFIG_TEMPLATE=/opt/hypercli-openclaw/openclaw.json
ENV HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com

WORKDIR /home/ubuntu
USER ubuntu

EXPOSE 18789
ENTRYPOINT ["/opt/hypercli-openclaw/entrypoint.sh"]
