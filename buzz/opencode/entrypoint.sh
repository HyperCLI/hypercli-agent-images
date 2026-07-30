#!/bin/sh
set -eu

config=/home/node/opencode.json
if [ ! -e "${config}" ] && [ ! -L "${config}" ]; then
  cp /opt/hypercli-buzz/opencode.json "${config}"
fi

exec /usr/local/bin/hypercli-buzz-entrypoint "$@"
