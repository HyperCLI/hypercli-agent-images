#!/usr/bin/env bash
set -euo pipefail

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

if ! path_ancestors_are_safe "${HERMES_HOME}/."; then
  echo "[hermes-agent] refusing symlinked HERMES_HOME ancestry: ${HERMES_HOME}" >&2
  exit 1
fi

mkdir -p "${HOME}" "${HERMES_HOME}" "${HERMES_SKILLS_DIR}" "${HYPER_WORKSPACES_DIR}"

# Hermes applies this managed scope after retained user dotenv files. Keep hosted
# launch credentials fresh without overwriting the retained volume.
export HERMES_MANAGED_DIR="${HERMES_PLATFORM_MANAGED_DIR}"
mkdir -p "${HERMES_MANAGED_DIR}"
python3 - "${HERMES_MANAGED_DIR}/.env" <<'PY'
import json
import os
from pathlib import Path
import sys

target = Path(sys.argv[1])
keys = (
    "API_SERVER_CORS_ORIGINS",
    "API_SERVER_ENABLED",
    "API_SERVER_HOST",
    "API_SERVER_KEY",
    "API_SERVER_MODEL_NAME",
    "API_SERVER_PORT",
    "HYPER_AGENTS_API_BASE",
    "HYPER_AGENTS_API_KEY",
    "OPENAI_API_KEY",
)
content = "".join(
    f"{key}={json.dumps(os.environ[key])}\n"
    for key in keys
    if key in os.environ
)
temporary = target.with_suffix(".tmp")
temporary.write_text(content, encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, target)
PY
chown -R -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${HERMES_MANAGED_DIR}"

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

if [[ ! -e "${MEM0_CONFIG_PATH}" && -e "${MEM0_CONFIG_TEMPLATE}" ]]; then
  cp "${MEM0_CONFIG_TEMPLATE}" "${MEM0_CONFIG_PATH}"
  echo "[hermes-agent] seeded default Mem0 config at ${MEM0_CONFIG_PATH}"
else
  echo "[hermes-agent] preserving existing Mem0 config at ${MEM0_CONFIG_PATH}"
fi
python3 /opt/hypercli-hermes/configure_mem0.py "${MEM0_CONFIG_PATH}"

chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${CONFIG_PATH}"
if [[ -e "${MEM0_CONFIG_PATH}" || -L "${MEM0_CONFIG_PATH}" ]]; then
  chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${MEM0_CONFIG_PATH}"
fi
chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${HOME}" "${HERMES_HOME}" "${HERMES_SKILLS_DIR}"
chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${HYPER_WORKSPACES_DIR}"
