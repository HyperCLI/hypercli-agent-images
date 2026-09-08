#!/usr/bin/env bash
set -euo pipefail

. /usr/local/lib/hypercli/desktop.sh

HOME="${HOME:-/home/hermes}"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HYPER_WORKSPACES_DIR="${HYPER_WORKSPACES_DIR:-${HOME}/shared}"
CONFIG_PATH="${HERMES_HOME}/config.yaml"
CONFIG_TEMPLATE="${HERMES_CONFIG_TEMPLATE:-/opt/hypercli-hermes/config.yaml}"
MEM0_CONFIG_PATH="${HERMES_HOME}/mem0.json"
MEM0_CONFIG_TEMPLATE="${MEM0_CONFIG_TEMPLATE:-/opt/hypercli-hermes/mem0.json}"
HYPERCLI_SKILLS_DIR="${HYPERCLI_SKILLS_DIR:-/opt/hypercli/skills}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-${HERMES_HOME}/skills}"
HERMES_PLATFORM_MANAGED_DIR="/run/hypercli-hermes-managed"
HERMES_MANAGED_DIR="${HERMES_MANAGED_DIR:-${HERMES_PLATFORM_MANAGED_DIR}}"
export HOME HERMES_HOME HYPER_WORKSPACES_DIR CONFIG_PATH CONFIG_TEMPLATE
export MEM0_CONFIG_PATH MEM0_CONFIG_TEMPLATE HYPERCLI_SKILLS_DIR HERMES_SKILLS_DIR
export HERMES_PLATFORM_MANAGED_DIR HERMES_MANAGED_DIR

if [[ -n "${HYPER_API_KEY:-}" && -z "${HYPER_AGENTS_API_KEY:-}" ]]; then
  export HYPER_AGENTS_API_KEY="${HYPER_API_KEY}"
fi

if [[ -n "${HYPER_AGENTS_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="${HYPER_AGENTS_API_KEY}"
fi

/opt/hypercli-hermes/init.sh
if hyper_desktop_enabled; then
  hyper_start_desktop
fi
exec /opt/hermes/docker/entrypoint-dispatch.sh "$@"
