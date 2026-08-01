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

link_if_missing "${HOME}/SKILLS.md" "/opt/hypercli-buzz/SKILLS.md"

for skill_file in /opt/hypercli/skills/*/SKILL.md; do
  skill_dir=${skill_file%/SKILL.md}
  skill=${skill_dir##*/}
  link_if_missing \
    "${nest}/.agents/skills/${skill}" \
    "${skill_dir}"
done

mkdir -p "${nest}/.claude/skills"
chmod 0700 "${nest}/.claude" "${nest}/.claude/skills"
for skill_dir in "${nest}/.agents/skills"/*; do
  skill=${skill_dir##*/}
  link_if_missing \
    "${nest}/.claude/skills/${skill}" \
    "../../.agents/skills/${skill}"
done
