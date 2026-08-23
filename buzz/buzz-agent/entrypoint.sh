#!/bin/sh
set -eu

# These are hosted defaults only. Buzz Desktop's resolved launch environment
# remains authoritative, including explicit empty values that should fail the
# native runtime's own validation rather than being silently replaced here.
if [ -z "${BUZZ_AGENT_PROVIDER+x}" ]; then
  export BUZZ_AGENT_PROVIDER=anthropic
fi
if [ -z "${BUZZ_AGENT_MODEL+x}" ]; then
  export BUZZ_AGENT_MODEL=coding-anthropic
fi
if [ -z "${ANTHROPIC_BASE_URL+x}" ]; then
  export ANTHROPIC_BASE_URL="${HYPER_API_BASE:?HYPER_API_BASE is required}"
fi
if [ -z "${ANTHROPIC_API_KEY+x}" ] && [ -n "${HYPER_AGENTS_API_KEY:-}" ]; then
  export ANTHROPIC_API_KEY="${HYPER_AGENTS_API_KEY}"
fi

exec /usr/local/bin/hypercli-buzz-entrypoint "$@"
