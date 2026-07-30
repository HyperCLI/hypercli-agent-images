#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 BASE_IMAGE" >&2
  exit 2
fi

image_config="$(docker image inspect --format '{{json .Config}}' "$1")"
python3 -c '
import json
import sys

config = json.loads(sys.argv[1])
assert config.get("Entrypoint") == [
    "/usr/bin/tini",
    "--",
    "/usr/local/bin/hypercli-coding-agent-entrypoint",
], config.get("Entrypoint")
assert config.get("Cmd") == ["sleep", "infinity"], config.get("Cmd")
healthcheck = config.get("Healthcheck")
assert healthcheck is None or healthcheck.get("Test") == ["NONE"], healthcheck
' "${image_config}"

docker run --rm \
  --entrypoint /bin/bash \
  "$1" -lc '
  set -euo pipefail
  test "$(id -u)" = 1000
  test "$(whoami)" = node
  test "$(sudo -n whoami)" = root
  test "$PWD" = /home/node
  test -d /home/node/workspaces
  test -s /opt/hypercli-coding-agent/.buzz-commit
  test ! -e /app/openclaw.mjs
  test ! -e /opt/hypercli-openclaw/entrypoint.sh
  ! command -v openclaw >/dev/null 2>&1
  command -v tini >/dev/null
  command -v git >/dev/null
  command -v ssh >/dev/null
  hyper --help >/dev/null
  buzz-acp --help >/dev/null
  buzz --help >/dev/null
  command -v buzz-dev-mcp >/dev/null
  test -x /usr/local/bin/hypercli-coding-agent-entrypoint
'

echo "$1: shared coding-agent base contract passed"
