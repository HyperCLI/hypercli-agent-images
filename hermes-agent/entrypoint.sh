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

path_ancestors_are_safe() {
  local path="$1"
  local parent component current=""
  parent="$(dirname -- "${path}")"
  IFS='/' read -r -a components <<< "${parent}"
  for component in "${components[@]}"; do
    [[ -n "${component}" ]] || continue
    current="${current}/${component}"
    if [[ -L "${current}" ]]; then
      return 1
    fi
  done
  return 0
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

if [[ -z "${HERMES_INFERENCE_API_BASE:-}" ]]; then
  export HERMES_INFERENCE_API_BASE="$(
    hermes_model_api_base_from_agents_base "${HYPER_AGENTS_API_BASE:-https://api.agents.hypercli.com}"
  )"
fi

if ! path_ancestors_are_safe "${HERMES_HOME}/."; then
  echo "[hermes-agent] refusing symlinked HERMES_HOME ancestry: ${HERMES_HOME}" >&2
  exit 1
fi

mkdir -p "${HERMES_HOME}" "${HERMES_SKILLS_DIR}" "${HYPER_WORKSPACES_DIR:-${HERMES_HOME}/workspaces}"

if [[ -L "${HERMES_SKILLS_DIR}" ]]; then
  echo "[hermes-agent] skipping bundled skill repair through symlink: ${HERMES_SKILLS_DIR}" >&2
elif [[ -d "${HYPERCLI_SKILLS_DIR}" ]]; then
  while IFS= read -r -d '' source_entry; do
    entry_name="${source_entry##*/}"
    target_entry="${HERMES_SKILLS_DIR}/${entry_name}"
    if [[ -L "${target_entry}" ]]; then
      echo "[hermes-agent] skipping bundled skill repair through symlink: ${target_entry}" >&2
      continue
    fi
    if [[ ! -e "${target_entry}" ]]; then
      cp -a "${source_entry}" "${target_entry}"
      echo "[hermes-agent] seeded HyperCLI skill (${entry_name})"
    fi
    # A retained volume may contain a bundled skill seeded by an older root
    # wrapper. Repair only paths present in the immutable image source manifest;
    # user-added files nested under the same skill directory remain untouched.
    # ``find -P`` and the ancestor fence avoid traversing user-controlled
    # symlinks; ``chown -h`` also leaves a final symlink target untouched.
    while IFS= read -r -d '' source_path; do
      relative_path="${source_path#"${source_entry}"}"
      target_path="${target_entry}${relative_path}"
      if path_ancestors_are_safe "${target_path}" && [[ -e "${target_path}" || -L "${target_path}" ]]; then
        chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${target_path}"
      fi
    done < <(find -P "${source_entry}" -print0)
  done < <(find "${HYPERCLI_SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)
fi

if [[ ! -e "${CONFIG_PATH}" ]]; then
  cp "${CONFIG_TEMPLATE}" "${CONFIG_PATH}"
  echo "[hermes-agent] seeded default config at ${CONFIG_PATH}"
else
  echo "[hermes-agent] preserving existing config at ${CONFIG_PATH}"
fi
chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${CONFIG_PATH}"

exec /opt/hermes/docker/entrypoint-dispatch.sh "$@"
