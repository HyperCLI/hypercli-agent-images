#!/bin/sh
set -eu

/usr/local/bin/hypercli-buzz-init

if [ "${1:-}" = "/usr/local/bin/hyper-acp" ] || [ "${1:-}" = "hyper-acp" ]; then
  : "${HYPER_ACP_AGENT_COMMAND:=/usr/local/lib/hyper-acp/plugins/buzz-acp}"
  export HYPER_ACP_AGENT_COMMAND

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
  : "${BUZZ_ACP_RELAY_OBSERVER:=false}"
  export BUZZ_ACP_RELAY_OBSERVER
fi

cd /home/node/.buzz
exec "$@"
