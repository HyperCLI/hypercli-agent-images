ARG OPENCLAW_PRO_BASE_IMAGE=ghcr.io/hypercli/hypercli-openclaw:prod

FROM ${OPENCLAW_PRO_BASE_IMAGE}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    openbox \
    sudo \
    websockify \
    x11vnc \
    xauth \
    xdg-utils \
    xvfb \
    && curl -fsSL -o /tmp/google-chrome-stable.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y --no-install-recommends /tmp/google-chrome-stable.deb \
    && rm -f /tmp/google-chrome-stable.deb \
    && echo "node ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/90-node-nopasswd \
    && chmod 0440 /etc/sudoers.d/90-node-nopasswd \
    && rm -rf /var/lib/apt/lists/*

ENV CHROME_EXECUTABLE_PATH=/usr/bin/google-chrome-stable
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable
ENV OPENCLAW_DESKTOP_ENABLED=0
ENV OPENCLAW_DESKTOP_PORT=3000
ENV OPENCLAW_MEMORY_SEARCH_ENABLED=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_ON_SESSION_START=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_ON_SEARCH=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_WATCH=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_WATCH_DEBOUNCE_MS=
ENV OPENCLAW_MEMORY_SEARCH_SYNC_INTERVAL_MINUTES=
ENV OPENCLAW_CONFIG_TEMPLATE=/opt/hypercli-openclaw/openclaw.json.pro

COPY --chown=node:node openclaw.json.pro /opt/hypercli-openclaw/openclaw.json.pro

EXPOSE 18789 3000
USER node
