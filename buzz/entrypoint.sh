#!/bin/sh
set -eu

/usr/local/bin/hypercli-buzz-init
cd /home/node/.buzz
exec "$@"
