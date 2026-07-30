#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 IMAGE EXPECTED_RUNTIME" >&2
  exit 2
fi

IMAGE="$1"
EXPECTED_RUNTIME="$2"

case "${EXPECTED_RUNTIME}" in
  opencode|codex|claude-code|goose|kimi-code) ;;
  *)
    echo "unsupported runtime: ${EXPECTED_RUNTIME}" >&2
    exit 2
    ;;
esac

image_config="$(docker image inspect --format '{{json .Config}}' "${IMAGE}")"
python3 -c '
import json
import sys

config = json.loads(sys.argv[1])
labels = config.get("Labels") or {}
env = dict(item.split("=", 1) for item in config.get("Env") or [] if "=" in item)

assert config.get("Entrypoint") == [
    "/usr/bin/tini",
    "--",
    "/usr/local/bin/hypercli-buzz-agent-entrypoint",
], config.get("Entrypoint")
assert config.get("WorkingDir") == "/home/node", config.get("WorkingDir")
assert config.get("Cmd") == ["sleep", "infinity"], config.get("Cmd")
assert labels.get("org.hypercli.buzz_runtime") == "true", labels
assert labels.get("org.hypercli.buzz_workspace") == "/home/node/.buzz", labels
assert labels.get("org.hypercli.coding_runtime") == sys.argv[2], labels
assert env.get("CODING_AGENT_WORKSPACE_DIR") == "/home/node/.buzz", env
assert env.get("HYPER_WORKSPACES_DIR") == "/home/node/workspaces", env
assert env.get("HYPERCLI_BUZZ_RUNTIME") == sys.argv[2], env
' "${image_config}" "${EXPECTED_RUNTIME}"

docker run --rm \
  --env EXPECTED_RUNTIME="${EXPECTED_RUNTIME}" \
  "${IMAGE}" /bin/bash -lc '
  set -euo pipefail
  test "$(id -u)" = 1000
  test "$(whoami)" = node
  test "$HOME" = /home/node
  test "$PWD" = /home/node/.buzz
  test "$CODING_AGENT_WORKSPACE_DIR" = /home/node/.buzz
  test "$HYPER_WORKSPACES_DIR" = /home/node/workspaces
  test -d /home/node/workspaces
  test ! -e /home/node/.buzz/workspaces
  test ! -e /opt/hypercli-coding-agent/buzz-nest/base_prompt.md
  test ! -e /home/node/.buzz/base_prompt.md

  for path in \
    /home/node/.buzz \
    /home/node/.buzz/GUIDES \
    /home/node/.buzz/RESEARCH \
    /home/node/.buzz/PLANS \
    /home/node/.buzz/WORK_LOGS \
    /home/node/.buzz/OUTBOX \
    /home/node/.buzz/REPOS \
    /home/node/.buzz/.scratch \
    /home/node/.buzz/.agents \
    /home/node/.buzz/.agents/skills \
    /home/node/.buzz/.agents/skills/buzz-cli; do
    test -d "$path"
    test "$(stat -c %a "$path")" = 700
  done

  cmp \
    /opt/hypercli-coding-agent/buzz-nest/AGENTS.md \
    /home/node/.buzz/AGENTS.md
  cmp \
    /opt/hypercli-coding-agent/buzz-nest/.agents/skills/buzz-cli/SKILL.md \
    /home/node/.buzz/.agents/skills/buzz-cli/SKILL.md
  test "$(stat -c %a /home/node/.buzz/AGENTS.md)" = 600
  test "$(stat -c %a /home/node/.buzz/.agents/skills/buzz-cli/SKILL.md)" = 600

  for skill_dir in .goose/skills .claude/skills .codex/skills; do
    link="/home/node/.buzz/$skill_dir/buzz-cli"
    test -L "$link"
    test "$(readlink "$link")" = ../../.agents/skills/buzz-cli
  done

  if [[ "$EXPECTED_RUNTIME" == claude-code ]]; then
    test -L /home/node/.buzz/CLAUDE.md
    test "$(readlink /home/node/.buzz/CLAUDE.md)" = AGENTS.md
  else
    test ! -e /home/node/.buzz/CLAUDE.md
  fi

  case "$EXPECTED_RUNTIME" in
    opencode)
      test -s /home/node/opencode.json
      test ! -e /home/node/.buzz/opencode.json
      ;;
    goose)
      test -s /home/node/.goose/config/config.yaml
      test -s /home/node/.goose/config/custom_providers/hypercli.json
      test ! -e /home/node/.buzz/.goose/config/config.yaml
      ;;
    kimi-code)
      test -s /home/node/.kimi-code/tui.toml
      test ! -e /home/node/.buzz/.kimi-code/tui.toml
      ;;
    codex)
      test ! -e /home/node/.buzz/.codex/auth.json
      ;;
    claude-code)
      test ! -e /home/node/.buzz/.claude/settings.json
      ;;
  esac
'

persisted_home="$(mktemp -d)"
bad_home="$(mktemp -d)"
trap 'rm -rf "${persisted_home}" "${bad_home}"' EXIT
chmod 0777 "${persisted_home}" "${bad_home}"

docker run --rm \
  --mount "type=bind,src=${persisted_home},dst=/home/node" \
  "${IMAGE}" /bin/bash -lc '
    set -euo pipefail
    test "$PWD" = /home/node/.buzz
    test -d /home/node/workspaces
    test ! -e /home/node/.buzz/workspaces
  '

printf '%s\n' 'user-managed AGENTS' >"${persisted_home}/.buzz/AGENTS.md"
printf '%s\n' 'user-managed skill' \
  >"${persisted_home}/.buzz/.agents/skills/buzz-cli/SKILL.md"
rm "${persisted_home}/.buzz/.goose/skills/buzz-cli"
printf '%s\n' 'user-managed goose link replacement' \
  >"${persisted_home}/.buzz/.goose/skills/buzz-cli"
if [[ "${EXPECTED_RUNTIME}" == "claude-code" ]]; then
  rm "${persisted_home}/.buzz/CLAUDE.md"
  printf '%s\n' 'user-managed Claude instructions' \
    >"${persisted_home}/.buzz/CLAUDE.md"
fi

docker run --rm \
  --mount "type=bind,src=${persisted_home},dst=/home/node" \
  "${IMAGE}" /bin/bash -lc '
    set -euo pipefail
    grep -Fx "user-managed AGENTS" /home/node/.buzz/AGENTS.md >/dev/null
    grep -Fx "user-managed skill" \
      /home/node/.buzz/.agents/skills/buzz-cli/SKILL.md >/dev/null
    test ! -L /home/node/.buzz/.goose/skills/buzz-cli
    grep -Fx "user-managed goose link replacement" \
      /home/node/.buzz/.goose/skills/buzz-cli >/dev/null
    if [[ "${HYPERCLI_BUZZ_RUNTIME}" == claude-code ]]; then
      test ! -L /home/node/.buzz/CLAUDE.md
      grep -Fx "user-managed Claude instructions" \
        /home/node/.buzz/CLAUDE.md >/dev/null
    fi
  '

mkdir -p "${bad_home}/workspaces"
ln -s workspaces "${bad_home}/.buzz"
if docker run --rm \
  --mount "type=bind,src=${bad_home},dst=/home/node" \
  "${IMAGE}" true; then
  echo "${IMAGE}: symlinked Buzz nest was unexpectedly accepted" >&2
  exit 1
fi
test -z "$(find "${bad_home}/workspaces" -mindepth 1 -print -quit)"

echo "${IMAGE}: ${EXPECTED_RUNTIME} Buzz nest contract passed"
