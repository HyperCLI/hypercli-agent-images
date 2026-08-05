#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: hypercli-kimi-auth <status|login> [arguments...]

Run Kimi Code's native authentication inside the hosted runtime.
  status  Report whether Kimi exposes a native status probe (currently unknown).
  login   Start Kimi's native device-code login.
EOF
}

action=${1:-}
if [ -z "${action}" ]; then
  usage >&2
  exit 2
fi
shift

case "${action}" in
  status)
    printf '%s\n' '{"runtime":"kimi-code","authenticated":null}'
    ;;
  login)
    exec /usr/local/bin/kimi login "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
