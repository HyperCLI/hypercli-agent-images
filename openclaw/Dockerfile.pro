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
    sudo \
    websockify \
    xxd \
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
COPY --chown=node:node entrypoint.sh /opt/hypercli-openclaw/entrypoint.sh
COPY --chown=node:node enable_slack_relay.ts /opt/hypercli-openclaw/enable_slack_relay.ts
COPY --chown=root:root chrome-wrapper.sh /usr/local/bin/hypercli-chrome
COPY --chown=root:root google-chrome.desktop /usr/share/applications/google-chrome.desktop
COPY --chown=root:root google-chrome.desktop /usr/share/applications/com.google.Chrome.desktop
RUN chmod +x /opt/hypercli-openclaw/entrypoint.sh /usr/local/bin/hypercli-chrome \
    && ln -sf /usr/local/bin/hypercli-chrome /usr/local/bin/google-chrome \
    && ln -sf /usr/local/bin/hypercli-chrome /usr/local/bin/google-chrome-stable \
    && install -d -o node -g node /home/node/Desktop \
    && install -m 0755 -o node -g node /usr/share/applications/google-chrome.desktop /home/node/Desktop/google-chrome.desktop \
    && printf '%s\n' \
      'alias google-chrome=/usr/local/bin/hypercli-chrome' \
      'alias google-chrome-stable=/usr/local/bin/hypercli-chrome' \
      >> /home/node/.bashrc

EXPOSE 18789 3000
USER node
