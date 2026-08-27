#!/usr/bin/env bash
set -euo pipefail

CHROME_BIN="${HYPERCLI_CHROME_BIN:-/usr/bin/google-chrome-stable}"
USER_DATA_DIR="${HYPERCLI_CHROME_USER_DATA_DIR:-${HOME:-/home/node}/.config/google-chrome}"

mkdir -p "${USER_DATA_DIR}"

exec "${CHROME_BIN}" \
  --no-sandbox \
  --disable-dev-shm-usage \
  --no-first-run \
  --no-default-browser-check \
  --disable-default-apps \
  --user-data-dir="${USER_DATA_DIR}" \
  "$@"
