#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
CONFIG_PATH="${HERMES_CONFIG_PATH:-${HERMES_HOME}/config.yaml}"
HYPERCLI_SKILLS_DIR="${HYPERCLI_SKILLS_DIR:-/opt/hypercli/skills}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-${HERMES_HOME}/skills}"

if [[ -n "${HYPER_API_KEY:-}" && -z "${HYPER_AGENTS_API_KEY:-}" ]]; then
  export HYPER_AGENTS_API_KEY="${HYPER_API_KEY}"
fi

mkdir -p "${HERMES_HOME}" "${HERMES_SKILLS_DIR}" "${HYPER_WORKSPACES_DIR:-${HERMES_HOME}/workspaces}"

if [[ -d "${HYPERCLI_SKILLS_DIR}" ]]; then
  while IFS= read -r -d '' source_entry; do
    entry_name="${source_entry##*/}"
    target_entry="${HERMES_SKILLS_DIR}/${entry_name}"
    if [[ ! -e "${target_entry}" ]]; then
      cp -a "${source_entry}" "${target_entry}"
      echo "[hermes-agent] seeded HyperCLI skill (${entry_name})"
    fi
  done < <(find "${HYPERCLI_SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0)
fi

if [[ ! -e "${CONFIG_PATH}" ]]; then
  HERMES_CONFIG_PATH="${CONFIG_PATH}" /opt/hermes/.venv/bin/python - <<'PY'
import os
from pathlib import Path

import yaml

path = Path(os.environ["HERMES_CONFIG_PATH"])
provider = os.environ.get("HERMES_MODEL_PROVIDER", "hypercli").strip() or "hypercli"
model = os.environ.get("HERMES_DEFAULT_MODEL", "kimi-k2.6-anthropic").strip()
base = (
    os.environ.get("HERMES_MODEL_API_BASE", "").strip()
    or os.environ.get("HYPER_AGENTS_API_BASE", "").strip()
    or "https://api.agents.hypercli.com"
).rstrip("/")
transport = os.environ.get("HERMES_MODEL_TRANSPORT", "anthropic_messages").strip()

config = {
    "model": {"provider": provider, "default": model},
    "providers": {
        provider: {
            "api": base,
            "key_env": "HYPER_AGENTS_API_KEY",
            "transport": transport,
            "default_model": model,
        }
    },
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
PY
  echo "[hermes-agent] seeded managed provider config at ${CONFIG_PATH}"
else
  echo "[hermes-agent] preserving existing config at ${CONFIG_PATH}"
fi

exec /opt/hermes/docker/entrypoint-dispatch.sh "$@"
