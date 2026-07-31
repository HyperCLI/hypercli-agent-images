#!/bin/sh
set -eu

config=/home/node/opencode.json
if [ ! -e "${config}" ] && [ ! -L "${config}" ]; then
  cp /opt/hypercli-buzz/opencode.json "${config}"
fi

/usr/local/bin/hypercli-buzz-init
/usr/local/bin/hypercli-buzz-opencode-policy

exec /usr/local/bin/hypercli-buzz-entrypoint "$@"
