#!/usr/bin/env bash

hyper_openclaw_slack_enabled() {
  case "$(printf '%s' "${HYPER_SLACK_APP_ENABLED:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

hyper_configure_openclaw_slack() {
  CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${OPENCLAW_STATE_DIR:-${HOME:-/home/node}/.openclaw}/openclaw.json}" \
    node /opt/hypercli-openclaw/slack.js

  if hyper_openclaw_slack_enabled; then
    if [[ -z "${HYPER_AGENTS_API_KEY:-}" ]]; then
      echo "[openclaw] HYPER_SLACK_APP_ENABLED requires HYPER_AGENTS_API_KEY" >&2
      exit 1
    fi
    if [[ -z "${HYPER_SLACK_API_URL:-}" ]]; then
      echo "[openclaw] HYPER_SLACK_APP_ENABLED requires HYPER_SLACK_API_URL" >&2
      exit 1
    fi
    export SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-${HYPER_AGENTS_API_KEY}}"
    export SLACK_API_URL="${SLACK_API_URL:-${HYPER_SLACK_API_URL}}"
  fi
}
