#!/bin/sh
set -eu

/usr/local/bin/hypercli-buzz-init

claude_dir=/home/node/.claude
settings="${claude_dir}/settings.json"
model="${BUZZ_ACP_MODEL:-kimi-k2.6-anthropic}"
mkdir -p "${claude_dir}"
if [ ! -e "${settings}" ] && [ ! -L "${settings}" ]; then
  umask 077
  jq -n --arg model "${model}" '{
    "$schema": "https://json.schemastore.org/claude-code-settings.json",
    model: $model,
    availableModels: [$model]
  }' > "${settings}"
fi

instructions=/home/node/.buzz/CLAUDE.md
if [ ! -e "${instructions}" ] && [ ! -L "${instructions}" ]; then
  ln -s AGENTS.md "${instructions}"
fi

cd /home/node/.buzz
exec /usr/local/bin/hypercli-buzz-entrypoint "$@"
