#!/bin/sh
set -eu

OPENCODE_TEMPLATE=/opt/hypercli-coding-agent/opencode.json
OPENCODE_CONFIG=/home/node/opencode.json
GOOSE_TEMPLATE=/opt/hypercli-coding-agent/goose-config.yaml
GOOSE_CONFIG=/home/node/.goose/config/config.yaml
GOOSE_PROVIDER_TEMPLATE=/opt/hypercli-coding-agent/goose-provider.json
GOOSE_PROVIDER_CONFIG=/home/node/.goose/config/custom_providers/hypercli.json
KIMI_TUI_TEMPLATE=/opt/hypercli-coding-agent/kimi-tui.toml
KIMI_TUI_CONFIG=/home/node/.kimi-code/tui.toml

if [ -f "${OPENCODE_TEMPLATE}" ] && [ ! -e "${OPENCODE_CONFIG}" ]; then
  cp "${OPENCODE_TEMPLATE}" "${OPENCODE_CONFIG}"
fi

if [ -f "${GOOSE_TEMPLATE}" ]; then
  if [ ! -e "${GOOSE_CONFIG}" ]; then
    mkdir -p "$(dirname "${GOOSE_CONFIG}")"
    cp "${GOOSE_TEMPLATE}" "${GOOSE_CONFIG}"
  fi
  if [ ! -e "${GOOSE_PROVIDER_CONFIG}" ]; then
    mkdir -p "$(dirname "${GOOSE_PROVIDER_CONFIG}")"
    cp "${GOOSE_PROVIDER_TEMPLATE}" "${GOOSE_PROVIDER_CONFIG}"
  fi
fi

if [ -f "${KIMI_TUI_TEMPLATE}" ] && [ ! -e "${KIMI_TUI_CONFIG}" ]; then
  mkdir -p "$(dirname "${KIMI_TUI_CONFIG}")"
  cp "${KIMI_TUI_TEMPLATE}" "${KIMI_TUI_CONFIG}"
fi

exec "$@"
