#!/usr/bin/env bash
set -euo pipefail

chrome_bin="${HYPERCLI_CHROME_BIN:-/usr/bin/google-chrome-stable}"
user_data_dir="${HYPERCLI_CHROME_USER_DATA_DIR:-${HOME:-/home/node}/.config/google-chrome}"
proxy_host="${HYPER_PROXY_HOST:-}"

# Boolean-ish true selects the canonical in-cluster hyper-proxy endpoint,
# boolean-ish false disables proxying; any other non-empty value is an
# explicit proxy URL passed through unchanged.
case "$(printf '%s' "${proxy_host}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on|enabled) proxy_host="socks5://hyper-proxy:8080" ;;
  0|false|no|off|disabled) proxy_host="" ;;
esac

mkdir -p "${user_data_dir}"

args=(
  --no-sandbox
  --disable-dev-shm-usage
  --no-first-run
  --no-default-browser-check
  --disable-default-apps
  --remote-debugging-address=127.0.0.1
  --remote-debugging-port=18800
  --user-data-dir="${user_data_dir}"
)

if [[ -n "${proxy_host}" ]]; then
  args+=(--proxy-server="${proxy_host}")
fi

exec "${chrome_bin}" "${args[@]}" "$@"
