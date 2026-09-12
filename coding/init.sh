#!/bin/sh
set -eu

umask 077

home=/home/node
template=/opt/hypercli-coding/nest

mkdir -p \
  "${home}/shared" \
  "${home}/GUIDES" \
  "${home}/RESEARCH" \
  "${home}/PLANS" \
  "${home}/WORK_LOGS" \
  "${home}/OUTBOX" \
  "${home}/REPOS" \
  "${home}/.scratch" \
  "${home}/.agents/skills"

chmod 0700 \
  "${home}/GUIDES" \
  "${home}/RESEARCH" \
  "${home}/PLANS" \
  "${home}/WORK_LOGS" \
  "${home}/OUTBOX" \
  "${home}/REPOS" \
  "${home}/.scratch" \
  "${home}/.agents" \
  "${home}/.agents/skills"

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

install_buzz_skill=false
if [ "$(cat /opt/hypercli-coding/runtime 2>/dev/null || true)" = "buzz-agent" ]; then
  install_buzz_skill=true
elif { [ "${1:-}" = "/usr/local/bin/acp" ] || [ "${1:-}" = "acp" ]; } \
  && [ "${2:-}" = "plugin" ] && [ "${3:-}" = "buzz" ]; then
  install_buzz_skill=true
fi

if [ "${install_buzz_skill}" = true ]; then
  mkdir -p "${home}/.agents/skills/buzz-cli"
  chmod 0700 "${home}/.agents/skills/buzz-cli"
  copy_if_missing \
    "${template}/.agents/skills/buzz-cli/SKILL.md" \
    "${home}/.agents/skills/buzz-cli/SKILL.md"
fi

link_if_missing "${HOME}/SKILLS.md" "/opt/hypercli-coding/SKILLS.md"

for skill_file in /opt/hypercli/skills/*/SKILL.md; do
  skill_dir=${skill_file%/SKILL.md}
  skill=${skill_dir##*/}
  link_if_missing \
    "${home}/.agents/skills/${skill}" \
    "${skill_dir}"
done

# Skill links belong to the runtime that owns the harness state directory: a
# coding image exposes installed skills only through its own harness directory
# so foreign harness dot-directories never appear in the synced workspace home.
runtime=$(cat /opt/hypercli-coding/runtime 2>/dev/null || true)
case "${runtime}" in
  claude-code) harness_dir=.claude ;;
  codex) harness_dir=.codex ;;
  goose) harness_dir=.goose ;;
  *) harness_dir= ;;
esac

if [ -n "${harness_dir}" ]; then
  mkdir -p "${home}/${harness_dir}/skills"
  chmod 0700 "${home}/${harness_dir}" "${home}/${harness_dir}/skills"
  for skill_dir in "${home}/.agents/skills"/*; do
    skill=${skill_dir##*/}
    link_if_missing \
      "${home}/${harness_dir}/skills/${skill}" \
      "../../.agents/skills/${skill}"
  done
fi
