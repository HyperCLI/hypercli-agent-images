#!/usr/bin/env bash
set -euo pipefail

USER_HOME="${HOME:-/home/node}"
STATE_DIR="${OPENCLAW_STATE_DIR:-${USER_HOME}/.openclaw}"
CONFIG_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-/opt/hypercli-openclaw/openclaw.json}"
CONFIG_PATH="${OPENCLAW_CONFIG_PATH:-${STATE_DIR}/openclaw.json}"
WORKSPACE_DIR="${STATE_DIR}/workspace"
HYPER_WORKSPACES_DIR="${HYPER_WORKSPACES_DIR:-${USER_HOME}/workspaces}"
SESSIONS_DIR="${STATE_DIR}/agents/default/sessions"
BRAVE_PLUGIN_PACKAGE="${OPENCLAW_BRAVE_PLUGIN_PACKAGE:-@openclaw/brave-plugin}"
BRAVE_PLUGIN_DIR="${STATE_DIR}/npm/node_modules/@openclaw/brave-plugin"
DESKTOP_ENABLED="${OPENCLAW_DESKTOP_ENABLED:-0}"
DESKTOP_PORT="${OPENCLAW_DESKTOP_PORT:-3000}"
DISPLAY="${DISPLAY:-:99}"
LOCAL_VNC_PORT=5900

mkdir -p "${WORKSPACE_DIR}" "${SESSIONS_DIR}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
  cp "${CONFIG_TEMPLATE}" "${CONFIG_PATH}"
fi

CONFIG_PATH="${CONFIG_PATH}" node <<'NODE'
const fs = require("fs");

const configPath = process.env.CONFIG_PATH;
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
const env = process.env;

function parseBoolean(name) {
  const raw = env[name];
  if (raw === undefined || raw === "") return undefined;
  switch (raw.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
    case "enabled":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
    case "disabled":
      return false;
    default:
      throw new Error(`${name} must be a boolean-like value`);
  }
}

function parseNonNegativeInteger(name) {
  const raw = env[name];
  if (raw === undefined || raw === "") return undefined;
  if (!/^\d+$/.test(raw.trim())) {
    throw new Error(`${name} must be a non-negative integer`);
  }
  return Number.parseInt(raw.trim(), 10);
}

const defaults = (((config.agents ||= {}).defaults ||= {}));
const memorySearch = ((defaults.memorySearch ||= {}));
const sync = ((memorySearch.sync ||= {}));
const workspaceIndexPath = "~/workspaces";
const extraPaths = Array.isArray(memorySearch.extraPaths) ? memorySearch.extraPaths : [];
if (!extraPaths.includes(workspaceIndexPath)) extraPaths.push(workspaceIndexPath);
memorySearch.extraPaths = extraPaths;

const enabled = parseBoolean("OPENCLAW_MEMORY_SEARCH_ENABLED");
if (enabled !== undefined) memorySearch.enabled = enabled;

const onSessionStart = parseBoolean("OPENCLAW_MEMORY_SEARCH_SYNC_ON_SESSION_START");
if (onSessionStart !== undefined) sync.onSessionStart = onSessionStart;

const onSearch = parseBoolean("OPENCLAW_MEMORY_SEARCH_SYNC_ON_SEARCH");
if (onSearch !== undefined) sync.onSearch = onSearch;

const watch = parseBoolean("OPENCLAW_MEMORY_SEARCH_SYNC_WATCH");
if (watch !== undefined) sync.watch = watch;

const watchDebounceMs = parseNonNegativeInteger("OPENCLAW_MEMORY_SEARCH_SYNC_WATCH_DEBOUNCE_MS");
if (watchDebounceMs !== undefined) sync.watchDebounceMs = watchDebounceMs;

const intervalMinutes = parseNonNegativeInteger("OPENCLAW_MEMORY_SEARCH_SYNC_INTERVAL_MINUTES");
if (intervalMinutes !== undefined) sync.intervalMinutes = intervalMinutes;

const desktopEnabled = parseBoolean("OPENCLAW_DESKTOP_ENABLED");
if (desktopEnabled === true) {
  const chromePath = env.CHROME_EXECUTABLE_PATH || "/usr/bin/google-chrome-stable";
  const browser = ((config.browser ||= {}));
  browser.enabled = true;
  browser.headless = false;
  browser.noSandbox = true;
  browser.executablePath = chromePath;
  if (typeof browser.defaultProfile !== "string" || !browser.defaultProfile) {
    browser.defaultProfile = "openclaw";
  }
  const profiles = ((browser.profiles ||= {}));
  const profile = ((profiles[browser.defaultProfile] ||= {}));
  if (profile.cdpPort === undefined) profile.cdpPort = 18800;
  if (profile.color === undefined) profile.color = "#FF4500";
  profile.headless = false;
  profile.executablePath = chromePath;
  const entries = (((config.plugins ||= {}).entries ||= {}));
  ((entries.browser ||= {})).enabled = true;
  const tools = ((config.tools ||= {}));
  if (!Array.isArray(tools.alsoAllow)) tools.alsoAllow = [];
  if (!tools.alsoAllow.includes("browser")) tools.alsoAllow.push("browser");
} else if (desktopEnabled === false) {
  if (config.browser && typeof config.browser === "object") {
    config.browser.enabled = false;
  }
  const entries = config.plugins && config.plugins.entries;
  if (entries && entries.browser && typeof entries.browser === "object") {
    entries.browser.enabled = false;
  }
  if (config.tools && Array.isArray(config.tools.alsoAllow)) {
    config.tools.alsoAllow = config.tools.alsoAllow.filter((tool) => tool !== "browser");
  }
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
NODE

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
  /usr/local/bin/openclaw plugins install --force "${BRAVE_PLUGIN_PACKAGE}"
fi
rm -f "${PLUGIN_INDEX_CHECK}"

/usr/local/bin/openclaw config validate
echo "[openclaw] config verified"

enabled() {
  local value="${1:-}"
  case "$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

desktop_enabled() {
  enabled "${DESKTOP_ENABLED}"
}

sync_workspaces() {
  if ! enabled "${HYPER_WORKSPACES_BOOT_SYNC:-0}"; then
    return 0
  fi
  if ! command -v hyper >/dev/null 2>&1; then
    echo "[openclaw] Workspaces boot sync requested but hyper is not on PATH" >&2
    return 1
  fi
  mkdir -p "${HYPER_WORKSPACES_DIR}"
  WORKSPACES_SYNC_ARGS=(workspaces sync)
  if [[ -n "${HYPER_WORKSPACES_SYNC_WORKSPACE:-}" ]]; then
    WORKSPACES_SYNC_ARGS+=("${HYPER_WORKSPACES_SYNC_WORKSPACE}")
  else
    WORKSPACES_SYNC_ARGS+=(--all)
  fi
  WORKSPACES_SYNC_ARGS+=(--output-dir "${HYPER_WORKSPACES_DIR}")
  if enabled "${HYPER_WORKSPACES_SYNC_READY_ONLY:-1}"; then
    WORKSPACES_SYNC_ARGS+=(--ready-only)
  fi
  echo "[openclaw] syncing Workspaces Markdown into ${HYPER_WORKSPACES_DIR}"
  hyper "${WORKSPACES_SYNC_ARGS[@]}"
}

run_workspaces_sync() {
  if sync_workspaces; then
    echo "[openclaw] Workspaces boot sync complete"
    return 0
  fi
  echo "[openclaw] Workspaces boot sync failed" >&2
  return 1
}

cleanup_desktop() {
  local pid
  for pid in "${NOVNC_PID:-}" "${X11VNC_PID:-}" "${XFCE_PANEL_PID:-}" "${XFWM_PID:-}" "${XVFB_PID:-}" "${DBUS_SESSION_BUS_PID:-}"; do
    if [[ -n "${pid}" ]]; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}

if enabled "${OPENCLAW_WORKSPACES_SYNC_ONLY:-0}"; then
  run_workspaces_sync
  exit $?
fi

if desktop_enabled; then
  if ! command -v Xvfb >/dev/null 2>&1 || ! command -v x11vnc >/dev/null 2>&1 || ! command -v websockify >/dev/null 2>&1 || ! command -v dbus-launch >/dev/null 2>&1 || ! command -v xfwm4 >/dev/null 2>&1 || ! command -v xfce4-panel >/dev/null 2>&1 || ! command -v xfce4-terminal >/dev/null 2>&1; then
    echo "[openclaw] desktop requested but desktop runtime packages are not installed" >&2
    exit 1
  fi
  export DISPLAY
  mkdir -p "${STATE_DIR}/desktop" "${STATE_DIR}/browser/openclaw/user-data"
  echo "[openclaw] starting desktop on ${DISPLAY}, noVNC port ${DESKTOP_PORT}"
  Xvfb "${DISPLAY}" -screen 0 1920x1080x24 -ac +extension RANDR &
  XVFB_PID="$!"
  sleep 1
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
  xfwm4 --replace >/tmp/xfwm4.log 2>&1 &
  XFWM_PID="$!"
  xfce4-panel >/tmp/xfce4-panel.log 2>&1 &
  XFCE_PANEL_PID="$!"
  x11vnc -display "${DISPLAY}" -rfbport "${LOCAL_VNC_PORT}" -localhost -forever -shared -nopw >/tmp/x11vnc.log 2>&1 &
  X11VNC_PID="$!"
  websockify --web /usr/share/novnc/ "${DESKTOP_PORT}" "localhost:${LOCAL_VNC_PORT}" >/tmp/novnc.log 2>&1 &
  NOVNC_PID="$!"
  trap cleanup_desktop EXIT INT TERM
fi

if enabled "${OPENCLAW_WORKSPACES_SYNC_HANDLED_BY_INIT:-0}"; then
  echo "[openclaw] Workspaces boot sync handled by Kubernetes init"
elif enabled "${HYPER_WORKSPACES_BOOT_SYNC:-0}"; then
  run_workspaces_sync || true
fi

echo "[openclaw] starting gateway on ${OPENCLAW_GATEWAY_BIND:-lan}:${OPENCLAW_PORT:-18789}"

exec /usr/local/bin/openclaw gateway run --port "${OPENCLAW_PORT:-18789}" --bind "${OPENCLAW_GATEWAY_BIND:-lan}"
