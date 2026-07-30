#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 IMAGE EXPECTED_RUNTIME" >&2
  exit 2
fi

IMAGE="$1"
EXPECTED_RUNTIME="$2"

case "${EXPECTED_RUNTIME}" in
  opencode)
    runtime_command=opencode
    runtime_args=acp
    ;;
  codex)
    runtime_command=codex-acp
    runtime_args=
    ;;
  claude-code)
    runtime_command=claude-agent-acp
    runtime_args=
    ;;
  *)
    echo "unsupported runtime: ${EXPECTED_RUNTIME}" >&2
    exit 2
    ;;
esac

docker run --rm \
  --entrypoint /bin/bash \
  --env EXPECTED_RUNTIME="${EXPECTED_RUNTIME}" \
  --env RUNTIME_COMMAND="${runtime_command}" \
  --env RUNTIME_ARGS="${runtime_args}" \
  "${IMAGE}" -lc '
  set -euo pipefail
  test "$(id -u)" = 1000
  test "$(whoami)" = node
  test "$(sudo -n whoami)" = root
  test "$PWD" = /home/node
  test "$(< /opt/hypercli-coding-agent/runtime)" = "$EXPECTED_RUNTIME"
  command -v "$RUNTIME_COMMAND" >/dev/null

  helper_args=(--agent-command "$RUNTIME_COMMAND")
  if [[ -n "$RUNTIME_ARGS" ]]; then
    helper_args+=(--agent-args "$RUNTIME_ARGS")
  fi

  timeout 90 buzz-acp auth-methods "${helper_args[@]}" --json >/tmp/auth-methods.json
  python3 -m json.tool /tmp/auth-methods.json >/dev/null
  python3 - "$EXPECTED_RUNTIME" /tmp/auth-methods.json <<'"'"'PY'"'"'
import json
import sys

expected = {
    "opencode": {"opencode-login"},
    "codex": {"api-key", "chat-gpt"},
    "claude-code": {"claude-ai-login", "console-login"},
}
payload = json.load(open(sys.argv[2], encoding="utf-8"))
method_ids = {
    method.get("id")
    for method in payload.get("methods", [])
    if isinstance(method, dict)
}
missing = expected[sys.argv[1]] - method_ids
assert not missing, (missing, payload)
PY

  case "$EXPECTED_RUNTIME" in
    opencode)
      opencode auth login --help >/tmp/login-help.txt 2>&1
      grep -F -- "--provider" /tmp/login-help.txt >/dev/null
      grep -F -- "--method" /tmp/login-help.txt >/dev/null
      opencode auth list >/tmp/auth-status.txt
      grep -F "0 credentials" /tmp/auth-status.txt >/dev/null
      ;;
    codex)
      codex login --help >/tmp/login-help.txt
      grep -F -- "--device-auth" /tmp/login-help.txt >/dev/null
      set +e
      codex login status >/tmp/auth-status.txt 2>&1
      auth_status=$?
      set -e
      test "$auth_status" -eq 1
      grep -F "Not logged in" /tmp/auth-status.txt >/dev/null
      ;;
    claude-code)
      claude auth login --help >/tmp/login-help.txt
      grep -F -- "--claudeai" /tmp/login-help.txt >/dev/null
      grep -F -- "--console" /tmp/login-help.txt >/dev/null
      grep -F -- "--sso" /tmp/login-help.txt >/dev/null
      set +e
      claude auth status --json >/tmp/auth-status.json
      auth_status=$?
      set -e
      test "$auth_status" -eq 1
      python3 -c \
        "import json; assert json.load(open(\"/tmp/auth-status.json\"))[\"loggedIn\"] is False"
      ;;
  esac

  if [[ "$EXPECTED_RUNTIME" == codex ]]; then
    if timeout 90 buzz-acp models "${helper_args[@]}" --json \
      >/tmp/models-unauthenticated.json 2>/tmp/models-unauthenticated.err; then
      echo "codex-acp unexpectedly created a session without authentication" >&2
      exit 1
    fi
    grep -F "Authentication required" /tmp/models-unauthenticated.err >/dev/null
    sanity_home="$(mktemp -d)"
    mkdir -p "${sanity_home}/.codex"
    printf "%s\n" "{\"OPENAI_API_KEY\":\"image-sanity-placeholder\"}" \
      >"${sanity_home}/.codex/auth.json"
    HOME="${sanity_home}" \
      timeout 90 buzz-acp models "${helper_args[@]}" --json >/tmp/models.json
  else
    timeout 90 buzz-acp models "${helper_args[@]}" --json >/tmp/models.json
  fi
  python3 -m json.tool /tmp/models.json >/dev/null
  grep -F "\"agent\":" /tmp/models.json >/dev/null
'

echo "${IMAGE}: ${EXPECTED_RUNTIME} image contract passed"
