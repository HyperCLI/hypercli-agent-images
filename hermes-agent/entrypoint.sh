#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
CONFIG_PATH="${HERMES_HOME}/config.yaml"
CONFIG_TEMPLATE="${HERMES_CONFIG_TEMPLATE:-/opt/hypercli-hermes/config.yaml}"
HYPERCLI_SKILLS_DIR="${HYPERCLI_SKILLS_DIR:-/opt/hypercli/skills}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-${HERMES_HOME}/skills}"

valid_id() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65534 ))
}

HERMES_OWNER_UID="${HERMES_UID:-${PUID:-10000}}"
HERMES_OWNER_GID="${HERMES_GID:-${PGID:-10000}}"
valid_id "${HERMES_OWNER_UID}" || HERMES_OWNER_UID=10000
valid_id "${HERMES_OWNER_GID}" || HERMES_OWNER_GID=10000

if [[ -n "${HYPER_API_KEY:-}" && -z "${HYPER_AGENTS_API_KEY:-}" ]]; then
  export HYPER_AGENTS_API_KEY="${HYPER_API_KEY}"
fi

hermes_model_api_base_from_agents_base() {
  local base="${1%/}"
  case "${base}" in
    https://api.dev.hypercli.com|https://api.dev.hypercli.com/*|\
    https://api.dev.hyperclaw.app|https://api.dev.hyperclaw.app/*|\
    https://dev-api.hyperclaw.app|https://dev-api.hyperclaw.app/*|\
    https://api.agents.dev.hypercli.com|https://api.agents.dev.hypercli.com/*)
      printf '%s' "https://api.agents.dev.hypercli.com/v1"
      ;;
    https://api.hypercli.com|https://api.hypercli.com/*|\
    https://api.hyperclaw.app|https://api.hyperclaw.app/*|\
    https://api.agents.hypercli.com|https://api.agents.hypercli.com/*)
      printf '%s' "https://api.agents.hypercli.com/v1"
      ;;
    */v1)
      printf '%s' "${base}"
      ;;
    */agents)
      printf '%s/v1' "${base%/agents}"
      ;;
    */api)
      printf '%s/v1' "${base%/api}"
      ;;
    *)
      printf '%s/v1' "${base}"
      ;;
  esac
}

if [[ -z "${HERMES_MODEL_API_BASE:-}" ]]; then
  export HERMES_MODEL_API_BASE="$(
    hermes_model_api_base_from_agents_base "${HYPER_AGENTS_API_BASE:-https://api.agents.hypercli.com}"
  )"
fi

mkdir -p "${HERMES_HOME}" "${HERMES_SKILLS_DIR}" "${HYPER_WORKSPACES_DIR:-${HERMES_HOME}/workspaces}"

if [[ -d "${HYPERCLI_SKILLS_DIR}" ]]; then
  while IFS= read -r -d '' source_entry; do
    entry_name="${source_entry##*/}"
    target_entry="${HERMES_SKILLS_DIR}/${entry_name}"
    if [[ ! -e "${target_entry}" ]]; then
      cp -a "${source_entry}" "${target_entry}"
      chown -R -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${target_entry}"
      echo "[hermes-agent] seeded HyperCLI skill (${entry_name})"
    fi
  done < <(find "${HYPERCLI_SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)
fi

if [[ ! -e "${CONFIG_PATH}" ]]; then
  cp "${CONFIG_TEMPLATE}" "${CONFIG_PATH}"
  echo "[hermes-agent] seeded default config at ${CONFIG_PATH}"
else
  echo "[hermes-agent] preserving existing config at ${CONFIG_PATH}"
fi

exec /opt/hermes/docker/entrypoint-dispatch.sh "$@"
