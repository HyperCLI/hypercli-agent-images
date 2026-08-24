#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
CONFIG_PATH="${HERMES_HOME}/config.yaml"
CONFIG_TEMPLATE="${HERMES_CONFIG_TEMPLATE:-/opt/hypercli-hermes/config.yaml}"
MEM0_CONFIG_PATH="${HERMES_MEM0_CONFIG_PATH:-${HERMES_HOME}/mem0.json}"
HYPERCLI_SKILLS_DIR="${HYPERCLI_SKILLS_DIR:-/opt/hypercli/skills}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-${HERMES_HOME}/skills}"
HERMES_PLATFORM_MANAGED_DIR="/run/hypercli-hermes-managed"

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

if [[ -n "${HYPER_AGENTS_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="${HYPER_AGENTS_API_KEY}"
fi

if ! path_ancestors_are_safe "${HERMES_HOME}/."; then
  echo "[hermes-agent] refusing symlinked HERMES_HOME ancestry: ${HERMES_HOME}" >&2
  exit 1
fi

mkdir -p "${HERMES_HOME}" "${HERMES_SKILLS_DIR}" "${HYPER_WORKSPACES_DIR:-${HERMES_HOME}/workspaces}"

if [[ -L "${MEM0_CONFIG_PATH}" ]]; then
  echo "[hermes-agent] skipping mem0 config seed through symlink: ${MEM0_CONFIG_PATH}" >&2
elif [[ ! -e "${MEM0_CONFIG_PATH}" ]]; then
  mkdir -p "$(dirname -- "${MEM0_CONFIG_PATH}")" "${HERMES_HOME}/mem0_qdrant"
  python3 - "${MEM0_CONFIG_PATH}" <<'PY'
import json
import os
from pathlib import Path
import sys

target = Path(sys.argv[1])
base_url = os.environ.get("HYPER_AGENTS_API_BASE", "https://api.agents.hypercli.com").rstrip("/")
llm_config = {
    "model": os.environ.get("HERMES_MEM0_LLM_MODEL", "default-anthropic"),
    "openai_base_url": f"{base_url}/v1",
}
embedder_config = {
    "model": os.environ.get("HERMES_MEM0_EMBEDDING_MODEL", "qwen3-embedding-4b"),
    "openai_base_url": f"{base_url}/v1",
}
embedding_dims = os.environ.get("HERMES_MEM0_EMBEDDING_DIMS", "2560").strip()
if embedding_dims:
    embedder_config["embedding_dims"] = int(embedding_dims)
config = {
    "mode": "oss",
    "agent_id": os.environ.get("MEM0_AGENT_ID", "hermes"),
    "oss": {
        "llm": {
            "provider": "openai",
            "config": llm_config,
        },
        "embedder": {
            "provider": "openai",
            "config": embedder_config,
        },
        "vector_store": {
            "provider": "qdrant",
            "config": {
                "path": os.environ.get("HERMES_MEM0_QDRANT_PATH", "/opt/data/mem0_qdrant"),
            },
        },
    },
}
temporary = target.with_suffix(".tmp")
temporary.write_text(json.dumps(config, indent=2, sort_keys=True) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, target)
PY
  echo "[hermes-agent] seeded mem0 OSS config at ${MEM0_CONFIG_PATH}"
else
  echo "[hermes-agent] preserving existing mem0 config at ${MEM0_CONFIG_PATH}"
fi

# Hermes intentionally lets a retained ~/.hermes/.env override the inherited
# process environment. Hosted launch credentials are different: Backend mints
# them for this exact runtime generation, so retained user state must not
# replace them. Hermes' native managed-scope overlay is applied after user
# dotenv files; project only the fixed platform-owned keys into that ephemeral
# overlay without modifying the retained volume.
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
if [[ -e "${MEM0_CONFIG_PATH}" || -L "${MEM0_CONFIG_PATH}" ]]; then
  chown -h -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${MEM0_CONFIG_PATH}"
fi
if [[ -d "${HERMES_HOME}/mem0_qdrant" ]]; then
  chown -R -- "${HERMES_OWNER_UID}:${HERMES_OWNER_GID}" "${HERMES_HOME}/mem0_qdrant"
fi

exec /opt/hermes/docker/entrypoint-dispatch.sh "$@"
