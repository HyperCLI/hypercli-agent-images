#!/bin/sh
set -eu

. /usr/local/lib/hypercli/desktop.sh

/usr/local/bin/hypercli-coding-init "$@"

if [ "${1:-}" = "/usr/local/bin/acp" ] || [ "${1:-}" = "acp" ]; then
  if [ -z "${HYPER_ACP_WS_URL:-}" ]; then
    base=${HYPER_AGENTS_API_BASE:-${HYPER_API_BASE:-https://api.agents.hypercli.com}}
    base=${base%/}
    case "${base}" in
      https://*) ws_base="wss://${base#https://}" ;;
      http://*) ws_base="ws://${base#http://}" ;;
      ws://*|wss://*) ws_base="${base}" ;;
      *) ws_base="wss://${base}" ;;
    esac
    ws_base=${ws_base%/agents}
    case "${ws_base}" in
      */ws) HYPER_ACP_WS_URL="${ws_base}" ;;
      *) HYPER_ACP_WS_URL="${ws_base}/ws" ;;
    esac
    export HYPER_ACP_WS_URL
  fi

  unset HYPER_ACP_WS_LISTEN HYPER_ACP_LOG
  permission_mode=$(printf '%s' "${HYPER_ACP_PERMISSION_MODE:-default}" | tr '[:upper:]' '[:lower:]')
  case "${permission_mode}" in
    default)
      HYPER_ACP_AUTO_APPROVE_PERMISSION=0
      ;;
    auto|bypass-permissions|bypasspermissions)
      HYPER_ACP_AUTO_APPROVE_PERMISSION=1
      ;;
    accept-edits|acceptedits|dont-ask|dontask|plan)
      HYPER_ACP_AUTO_APPROVE_PERMISSION=0
      ;;
    *)
      echo "HYPER_ACP_PERMISSION_MODE must be default, auto, bypass-permissions, accept-edits, dont-ask, or plan" >&2
      exit 1
      ;;
  esac
  export HYPER_ACP_AUTO_APPROVE_PERMISSION
  if [ "${2:-}" = "plugin" ] && [ "${3:-}" = "buzz" ]; then
    : "${BUZZ_ACP_RELAY_OBSERVER:=true}"
    export BUZZ_ACP_RELAY_OBSERVER
  fi
fi

if hyper_desktop_enabled; then
  hyper_start_desktop
fi

cd /home/node
exec "$@"
