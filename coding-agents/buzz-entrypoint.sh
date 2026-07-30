#!/bin/sh
set -eu

umask 077

BUZZ_NEST=/home/node/.buzz
BUZZ_NEST_TEMPLATE=/opt/hypercli-coding-agent/buzz-nest
GENERIC_ENTRYPOINT=/usr/local/bin/hypercli-coding-agent-entrypoint

if [ -L "${BUZZ_NEST}" ]; then
  echo "refusing symlinked Buzz nest: ${BUZZ_NEST}" >&2
  exit 1
fi

mkdir -p /home/node/workspaces
mkdir -p \
  "${BUZZ_NEST}/GUIDES" \
  "${BUZZ_NEST}/RESEARCH" \
  "${BUZZ_NEST}/PLANS" \
  "${BUZZ_NEST}/WORK_LOGS" \
  "${BUZZ_NEST}/OUTBOX" \
  "${BUZZ_NEST}/REPOS" \
  "${BUZZ_NEST}/.scratch" \
  "${BUZZ_NEST}/.agents/skills/buzz-cli"

chmod 0700 \
  "${BUZZ_NEST}" \
  "${BUZZ_NEST}/GUIDES" \
  "${BUZZ_NEST}/RESEARCH" \
  "${BUZZ_NEST}/PLANS" \
  "${BUZZ_NEST}/WORK_LOGS" \
  "${BUZZ_NEST}/OUTBOX" \
  "${BUZZ_NEST}/REPOS" \
  "${BUZZ_NEST}/.scratch" \
  "${BUZZ_NEST}/.agents" \
  "${BUZZ_NEST}/.agents/skills" \
  "${BUZZ_NEST}/.agents/skills/buzz-cli"

copy_if_missing() {
  source_path=$1
  destination_path=$2
  if [ ! -e "${destination_path}" ] && [ ! -L "${destination_path}" ]; then
    cp "${source_path}" "${destination_path}"
    chmod 0600 "${destination_path}"
  fi
}

link_if_missing() {
  link_path=$1
  link_target=$2
  if [ ! -e "${link_path}" ] && [ ! -L "${link_path}" ]; then
    ln -s "${link_target}" "${link_path}"
  fi
}

copy_if_missing \
  "${BUZZ_NEST_TEMPLATE}/AGENTS.md" \
  "${BUZZ_NEST}/AGENTS.md"
copy_if_missing \
  "${BUZZ_NEST_TEMPLATE}/.agents/skills/buzz-cli/SKILL.md" \
  "${BUZZ_NEST}/.agents/skills/buzz-cli/SKILL.md"

for skill_dir in .goose/skills .claude/skills .codex/skills; do
  mkdir -p "${BUZZ_NEST}/${skill_dir}"
  chmod 0700 \
    "${BUZZ_NEST}/${skill_dir%%/*}" \
    "${BUZZ_NEST}/${skill_dir}"
  link_if_missing \
    "${BUZZ_NEST}/${skill_dir}/buzz-cli" \
    "../../.agents/skills/buzz-cli"
done

if [ "${HYPERCLI_BUZZ_RUNTIME:-}" = "claude-code" ]; then
  link_if_missing "${BUZZ_NEST}/CLAUDE.md" "AGENTS.md"
fi

cd "${BUZZ_NEST}"
exec "${GENERIC_ENTRYPOINT}" "$@"
