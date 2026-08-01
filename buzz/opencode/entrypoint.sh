#!/bin/sh
set -eu

config_dir=${XDG_CONFIG_HOME:-/home/node/.config}/opencode
config=${config_dir}/opencode.json
mkdir -p "${config_dir}"
if [ ! -e "${config}" ] && [ ! -L "${config}" ]; then
  cp /opt/hypercli-buzz/opencode.json "${config}"
fi

/usr/local/bin/hypercli-buzz-init
/usr/local/bin/hypercli-buzz-opencode-policy

exec /usr/local/bin/hypercli-buzz-entrypoint "$@"
