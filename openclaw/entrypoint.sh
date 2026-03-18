#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/ubuntu
export DISPLAY="${DISPLAY:-:99}"
export HYPER_API_KEY="${HYPER_API_KEY:-}"
export HYPER_API_BASE="${HYPER_API_BASE:-https://api.agents.hypercli.com}"
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-${HOME}/.openclaw}"
export OPENCLAW_CONFIG_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-/opt/hypercli-openclaw/openclaw.json}"
export OPENCLAW_CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR}/openclaw.json}"

mkdir -p \
  "${OPENCLAW_STATE_DIR}" \
  "${OPENCLAW_STATE_DIR}/workspace" \
  "${OPENCLAW_STATE_DIR}/agents/default/sessions" \
  /tmp
chmod 700 "${OPENCLAW_STATE_DIR}" "${OPENCLAW_STATE_DIR}/agents" "${OPENCLAW_STATE_DIR}/agents/default" "${OPENCLAW_STATE_DIR}/agents/default/sessions" 2>/dev/null || true

if [[ ! -f "${OPENCLAW_CONFIG_PATH}" ]]; then
  cp "${OPENCLAW_CONFIG_TEMPLATE}" "${OPENCLAW_CONFIG_PATH}"
fi

chmod 600 "${OPENCLAW_CONFIG_PATH}" 2>/dev/null || true

HOME="${HOME}" openclaw config validate >/dev/null
echo "[openclaw] config verified"

Xvfb "${DISPLAY}" -screen 0 1920x1080x24 -ac +extension RANDR > /tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 1

openbox > /tmp/openbox.log 2>&1 &
OPENBOX_PID=$!

x11vnc -display "${DISPLAY}" -rfbport 5900 -forever -shared -nopw > /tmp/x11vnc.log 2>&1 &
X11VNC_PID=$!

start_novnc() {
  websockify --web /usr/share/novnc/ 3000 localhost:5900 > /tmp/novnc.log 2>&1 &
  NOVNC_PID=$!
}

find_gateway_pid() {
  pgrep -u "$(id -u)" -f '(^|/)openclaw-gateway([[:space:]]|$)' | head -n 1 || true
}

start_gateway() {
  openclaw gateway run --port "${OPENCLAW_PORT:-18789}" --bind "${OPENCLAW_GATEWAY_BIND:-lan}" >> /tmp/openclaw-gw.log 2>&1 &
  GATEWAY_LAUNCH_PID=$!
  sleep 1
  GATEWAY_PID="$(find_gateway_pid)"
  if [[ -z "${GATEWAY_PID}" ]]; then
    GATEWAY_PID="${GATEWAY_LAUNCH_PID}"
  fi
  echo "[openclaw] gateway started"
}

start_novnc
start_gateway

cleanup() {
  kill "${GATEWAY_LAUNCH_PID:-}" "${GATEWAY_PID:-}" "${NOVNC_PID:-}" "${X11VNC_PID:-}" "${OPENBOX_PID:-}" "${XVFB_PID:-}" 2>/dev/null || true
  pkill -u "$(id -u)" -f '(^|/)openclaw-gateway([[:space:]]|$)' 2>/dev/null || true
  wait || true
}

trap cleanup SIGINT SIGTERM

while true; do
  wait -n "${GATEWAY_PID}" "${NOVNC_PID}" "${X11VNC_PID}" "${OPENBOX_PID}" "${XVFB_PID}" 2>/dev/null || true
  for pid in "${X11VNC_PID}" "${OPENBOX_PID}" "${XVFB_PID}"; do
    if ! kill -0 "${pid}" 2>/dev/null; then
      cleanup
      exit 1
    fi
  done
  if ! kill -0 "${NOVNC_PID}" 2>/dev/null; then
    sleep 2
    start_novnc
  fi
  if ! kill -0 "${GATEWAY_PID}" 2>/dev/null; then
    GATEWAY_PID="$(find_gateway_pid)"
    if [[ -z "${GATEWAY_PID}" ]]; then
      sleep 2
      start_gateway
    fi
  fi
done
