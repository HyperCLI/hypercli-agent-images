#!/usr/bin/env bash
set -euo pipefail

REAL_OPENCLAW="${REAL_OPENCLAW:-/usr/local/bin/openclaw-real}"

find_gateway_pid() {
  pgrep -u "$(id -u)" -f '(^|/)openclaw-gateway([[:space:]]|$)' | head -n 1 || true
}

if [[ "${1:-}" == "gateway" && "${2:-}" == "restart" ]]; then
  pid="$(find_gateway_pid)"
  if [[ -z "${pid}" ]]; then
    echo "OpenClaw gateway is not running; starting it via supervisor is required."
    echo "If this is the container image, use the container entrypoint or start 'openclaw gateway run' in the foreground."
    exit 1
  fi
  kill -TERM "${pid}"
  for _ in $(seq 1 30); do
    sleep 1
    next_pid="$(find_gateway_pid)"
    if [[ -n "${next_pid}" && "${next_pid}" != "${pid}" ]]; then
      echo "OpenClaw gateway restarted (PID ${next_pid})"
      exit 0
    fi
  done
  echo "OpenClaw gateway restart timed out waiting for supervisor respawn" >&2
  exit 1
fi

exec "${REAL_OPENCLAW}" "$@"
