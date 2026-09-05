# syntax=docker/dockerfile:1.7

ARG NODE_IMAGE=docker.io/library/node:24-bookworm-slim@sha256:6f7b03f7c2c8e2e784dcf9295400527b9b1270fd37b7e9a7285cf83b6951452d
ARG HYPERCLI_REF=main
ARG HYPERCLI_SHA
ARG HYPERCLI_REPO=https://github.com/HyperCLI/hypercli.git

FROM ${NODE_IMAGE}

ARG NODE_IMAGE
ARG HYPERCLI_REF
ARG HYPERCLI_SHA
ARG HYPERCLI_REPO

LABEL org.opencontainers.image.source="https://github.com/HyperCLI/hyperclaw-backend" \
      org.opencontainers.image.title="HyperCLI Agent Base" \
      org.opencontainers.image.base.name="${NODE_IMAGE}" \
      org.hypercli.hypercli_ref="${HYPERCLI_REF}" \
      org.hypercli.hypercli_sha="${HYPERCLI_SHA}"

ENV HYPERCLI_REF=${HYPERCLI_REF}
ENV HYPERCLI_SHA=${HYPERCLI_SHA}
ENV DEBIAN_FRONTEND=noninteractive

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    jq \
    ffmpeg \
    poppler-utils \
    lsof \
    openssh-client \
    procps \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    ripgrep \
    build-essential \
    sudo \
    tini \
    vim \
    xxd \
    nano \
    zip \
    unzip \
    dbus-x11 \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    novnc \
    thunar \
    websockify \
    x11vnc \
    xauth \
    xdg-utils \
    xfce4-panel \
    xfce4-terminal \
    xfwm4 \
    xvfb \
    && curl -fsSL -o /tmp/google-chrome-stable.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y --no-install-recommends /tmp/google-chrome-stable.deb \
    && rm -f /tmp/google-chrome-stable.deb \
    && if [ ! -s /var/lib/dbus/machine-id ]; then dbus-uuidgen >/var/lib/dbus/machine-id; fi \
    && ln -sf /var/lib/dbus/machine-id /etc/machine-id \
    && printf '%s\n' 'node ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-node-nopasswd \
    && chmod 0440 /etc/sudoers.d/90-node-nopasswd \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/lib/hypercli /home/node/shared /home/node/Desktop \
    && chown -R node:node /home/node

RUN checkout_ref="${HYPERCLI_SHA:-${HYPERCLI_REF}}" && \
    test -n "${checkout_ref}" && \
    git clone --depth 1 "${HYPERCLI_REPO}" /opt/hypercli && \
    git -C /opt/hypercli fetch --depth 1 origin "${checkout_ref}" && \
    git -C /opt/hypercli checkout FETCH_HEAD && \
    { test -z "${HYPERCLI_SHA}" || test "$(git -C /opt/hypercli rev-parse HEAD)" = "${HYPERCLI_SHA}"; } && \
    test -n "$(find /opt/hypercli/skills -type f -name SKILL.md -print -quit)" && \
    python3 -m venv /opt/hypercli/venv && \
    /opt/hypercli/venv/bin/pip install --no-cache-dir /opt/hypercli/sdk "/opt/hypercli/cli[all]" && \
    /opt/hypercli/venv/bin/hyper --help >/dev/null && \
    ln -sf /opt/hypercli/venv/bin/hyper /usr/local/bin/hyper

COPY desktop.sh /usr/local/lib/hypercli/desktop.sh
COPY google-chrome.desktop /usr/share/applications/google-chrome.desktop
COPY google-chrome.desktop /usr/share/applications/com.google.Chrome.desktop
RUN chmod 0644 /usr/local/lib/hypercli/desktop.sh /usr/share/applications/google-chrome.desktop /usr/share/applications/com.google.Chrome.desktop \
    && install -m 0755 -o node -g node /usr/share/applications/google-chrome.desktop /home/node/Desktop/google-chrome.desktop

ENV HOME=/home/node \
    HYPER_AGENTS_API_BASE=https://api.agents.hypercli.com \
    HYPER_API_BASE=https://api.hypercli.com \
    HYPER_AGENTS_WEB_SEARCH_BASE=https://api.agents.hypercli.com/agents/brave \
    HYPER_WORKSPACES_DIR=/home/node/shared \
    HYPER_DESKTOP_ENABLED=0 \
    HYPER_DESKTOP_PORT=3000 \
    HYPER_DESKTOP_GEOMETRY=1280x800x24 \
    DISPLAY=:99 \
    CHROME_EXECUTABLE_PATH=/usr/bin/google-chrome-stable \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable \
    PATH=/opt/hypercli/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /home/node
USER node
HEALTHCHECK NONE
