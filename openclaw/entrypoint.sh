#!/usr/bin/env bash
set -euo pipefail

USER_HOME="${HOME:-/home/node}"
STATE_DIR="${OPENCLAW_STATE_DIR:-${USER_HOME}/.openclaw}"
CONFIG_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-/opt/hypercli-openclaw/openclaw.json}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${STATE_DIR}/openclaw.json}"
WORKSPACE_DIR="${STATE_DIR}/workspace"
SESSIONS_DIR="${STATE_DIR}/agents/default/sessions"
BRAVE_PLUGIN_PACKAGE="${OPENCLAW_BRAVE_PLUGIN_PACKAGE:-@openclaw/brave-plugin}"
BRAVE_PLUGIN_DIR="${STATE_DIR}/npm/node_modules/@openclaw/brave-plugin"

mkdir -p "${WORKSPACE_DIR}" "${SESSIONS_DIR}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  cp "${CONFIG_TEMPLATE}" "${CONFIG_PATH}"
fi

OPENCLAW_VERSION="$(node -e 'try { console.log(require("/app/package.json").version || "") } catch { process.exit(1) }' 2>/dev/null || true)"
if [[ "${BRAVE_PLUGIN_PACKAGE}" == "@openclaw/brave-plugin" && -n "${OPENCLAW_VERSION}" ]]; then
  BRAVE_PLUGIN_PACKAGE="@openclaw/brave-plugin@${OPENCLAW_VERSION}"
fi
BRAVE_PLUGIN_EXPECTED_VERSION="${BRAVE_PLUGIN_PACKAGE##*@}"

PLUGIN_INDEX_CHECK="${STATE_DIR}/.plugins-list.json"
INSTALL_BRAVE_PLUGIN=0
if ! /usr/local/bin/openclaw plugins list --json >"${PLUGIN_INDEX_CHECK}" 2>/dev/null || ! grep -q '"id": "brave"' "${PLUGIN_INDEX_CHECK}"; then
  INSTALL_BRAVE_PLUGIN=1
elif [[ -f "${BRAVE_PLUGIN_DIR}/package.json" && -n "${OPENCLAW_VERSION}" ]]; then
  BRAVE_PLUGIN_INSTALLED_VERSION="$(node -e 'try { console.log(require(process.argv[1]).version || "") } catch { process.exit(1) }' "${BRAVE_PLUGIN_DIR}/package.json" 2>/dev/null || true)"
  if [[ "${BRAVE_PLUGIN_EXPECTED_VERSION}" == "${OPENCLAW_VERSION}" && "${BRAVE_PLUGIN_INSTALLED_VERSION}" != "${OPENCLAW_VERSION}" ]]; then
    echo "[openclaw] Brave plugin version ${BRAVE_PLUGIN_INSTALLED_VERSION:-unknown} does not match OpenClaw ${OPENCLAW_VERSION}"
    INSTALL_BRAVE_PLUGIN=1
  fi
fi

if [[ "${INSTALL_BRAVE_PLUGIN}" == "1" ]]; then
  echo "[openclaw] installing Brave web search plugin (${BRAVE_PLUGIN_PACKAGE})"
  /usr/local/bin/openclaw plugins install "${BRAVE_PLUGIN_PACKAGE}"
fi
rm -f "${PLUGIN_INDEX_CHECK}"

node /opt/hypercli-openclaw/configure-openclaw-web-search.mjs "${CONFIG_PATH}"

/usr/local/bin/openclaw config validate
echo "[openclaw] config verified"
echo "[openclaw] starting gateway on ${OPENCLAW_GATEWAY_BIND:-lan}:${OPENCLAW_PORT:-18789}"

exec /usr/local/bin/openclaw gateway run --port "${OPENCLAW_PORT:-18789}" --bind "${OPENCLAW_GATEWAY_BIND:-lan}"
