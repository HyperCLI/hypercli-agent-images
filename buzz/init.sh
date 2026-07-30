#!/bin/sh
set -eu

umask 077

nest=/home/node/.buzz
template=/opt/hypercli-buzz/nest

if [ -L "${nest}" ]; then
  echo "refusing symlinked Buzz nest: ${nest}" >&2
  exit 1
fi

mkdir -p \
  /home/node/workspaces \
  "${nest}/GUIDES" \
  "${nest}/RESEARCH" \
  "${nest}/PLANS" \
  "${nest}/WORK_LOGS" \
  "${nest}/OUTBOX" \
  "${nest}/REPOS" \
  "${nest}/.scratch" \
  "${nest}/.agents/skills/buzz-cli"

chmod 0700 \
  "${nest}" \
  "${nest}/GUIDES" \
  "${nest}/RESEARCH" \
  "${nest}/PLANS" \
  "${nest}/WORK_LOGS" \
  "${nest}/OUTBOX" \
  "${nest}/REPOS" \
  "${nest}/.scratch" \
  "${nest}/.agents" \
  "${nest}/.agents/skills" \
  "${nest}/.agents/skills/buzz-cli"

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

copy_if_missing "${template}/AGENTS.md" "${nest}/AGENTS.md"
copy_if_missing \
  "${template}/.agents/skills/buzz-cli/SKILL.md" \
  "${nest}/.agents/skills/buzz-cli/SKILL.md"

for skill_dir in .goose/skills .claude/skills .codex/skills; do
  mkdir -p "${nest}/${skill_dir}"
  chmod 0700 "${nest}/${skill_dir%%/*}" "${nest}/${skill_dir}"
  link_if_missing \
    "${nest}/${skill_dir}/buzz-cli" \
    "../../.agents/skills/buzz-cli"
done
