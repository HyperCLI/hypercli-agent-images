#!/bin/sh
set -eu

/usr/local/bin/hypercli-buzz-init

instructions=/home/node/.buzz/CLAUDE.md
if [ ! -e "${instructions}" ] && [ ! -L "${instructions}" ]; then
  ln -s AGENTS.md "${instructions}"
fi

cd /home/node/.buzz
exec "$@"
