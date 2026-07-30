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
  goose)
    runtime_command=goose
    runtime_args=acp
    ;;
  kimi-code)
    runtime_command=kimi
    runtime_args=acp
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

  if [[ "$EXPECTED_RUNTIME" == goose ]]; then
    export HYPER_AGENTS_API_KEY=image-sanity-placeholder
    mkdir -p "${GOOSE_PATH_ROOT}/config"
    mkdir -p "${GOOSE_PATH_ROOT}/config/custom_providers"
    cp /opt/hypercli-coding-agent/goose-config.yaml \
      "${GOOSE_PATH_ROOT}/config/config.yaml"
    cp /opt/hypercli-coding-agent/goose-provider.json \
      "${GOOSE_PATH_ROOT}/config/custom_providers/hypercli.json"
  fi

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
    "goose": {"goose-provider"},
    "kimi-code": {"login"},
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
    goose)
      goose --version >/tmp/runtime-version.txt
      goose acp --help >/tmp/acp-help.txt
      grep -F "ACP agent server on stdio" /tmp/acp-help.txt >/dev/null
      ;;
    kimi-code)
      kimi --version >/tmp/runtime-version.txt
      kimi acp --help >/tmp/acp-help.txt
      kimi login --help >/tmp/login-help.txt
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
  elif [[ "$EXPECTED_RUNTIME" != kimi-code ]]; then
    timeout 90 buzz-acp models "${helper_args[@]}" --json >/tmp/models.json
  fi
  if [[ -e /tmp/models.json ]]; then
    python3 -m json.tool /tmp/models.json >/dev/null
    grep -F "\"agent\":" /tmp/models.json >/dev/null
  fi
'

if [[ "${EXPECTED_RUNTIME}" == "opencode" ]]; then
  persisted_home="$(mktemp -d)"
  trap 'rm -rf "${persisted_home}"' EXIT
  chmod 0777 "${persisted_home}"

  assert_recovered_config() {
    docker run --rm \
      --mount "type=bind,src=${persisted_home},dst=/home/node" \
      "${IMAGE}" /bin/bash -lc '
        set -euo pipefail
        test -s /home/node/opencode.json
        python3 - <<'"'"'PY'"'"'
import json

with open("/home/node/opencode.json", encoding="utf-8") as config_file:
    config = json.load(config_file)

provider = config["provider"]["hypercli"]
assert provider["options"]["baseURL"] == "{env:HYPER_API_BASE}/v1"
assert provider["options"]["apiKey"] == "{env:HYPER_AGENTS_API_KEY}"
assert set(provider["models"]) == {"kimi-k2.6-anthropic"}
assert config["model"] == "hypercli/kimi-k2.6-anthropic"
PY
      '
  }

  assert_recovered_config
  rm -f "${persisted_home}/opencode.json"
  assert_recovered_config

  printf '%s\n' '{"userManaged":true}' >"${persisted_home}/opencode.json"
  docker run --rm \
    --mount "type=bind,src=${persisted_home},dst=/home/node" \
    "${IMAGE}" /bin/bash -lc \
      'grep -Fx '\''{"userManaged":true}'\'' /home/node/opencode.json >/dev/null'
fi

if [[ "${EXPECTED_RUNTIME}" == "goose" ]]; then
  persisted_home="$(mktemp -d)"
  trap 'rm -rf "${persisted_home}"' EXIT
  chmod 0777 "${persisted_home}"

  assert_recovered_goose_config() {
    docker run --rm \
      --env HYPER_AGENTS_API_KEY=image-sanity-placeholder \
      --env HYPER_AGENTS_API_BASE=https://api.agents.example.invalid \
      --mount "type=bind,src=${persisted_home},dst=/home/node" \
      "${IMAGE}" /bin/bash -lc '
        set -euo pipefail
        test -s /home/node/.goose/config/config.yaml
        test -s /home/node/.goose/config/custom_providers/hypercli.json
        test -z "${ANTHROPIC_API_KEY:-}"
        test -z "${ANTHROPIC_HOST:-}"
        grep -F "active_provider: hypercli" \
          /home/node/.goose/config/config.yaml >/dev/null
        grep -F "model: kimi-k2.6-anthropic" \
          /home/node/.goose/config/config.yaml >/dev/null
        python3 - <<'"'"'PY'"'"'
import json

with open(
    "/home/node/.goose/config/custom_providers/hypercli.json",
    encoding="utf-8",
) as provider_file:
    provider = json.load(provider_file)

assert provider["engine"] == "anthropic"
assert provider["api_key_env"] == "HYPER_AGENTS_API_KEY"
assert provider["base_url"] == "${HYPER_AGENTS_API_BASE}"
assert [model["name"] for model in provider["models"]] == [
    "kimi-k2.6-anthropic"
]
assert provider["dynamic_models"] is False
assert provider["preserves_thinking"] is True
PY
      '
  }

  assert_recovered_goose_config
  rm -f "${persisted_home}/.goose/config/config.yaml"
  rm -f "${persisted_home}/.goose/config/custom_providers/hypercli.json"
  assert_recovered_goose_config

  printf '%s\n' 'user_managed: true' \
    >"${persisted_home}/.goose/config/config.yaml"
  docker run --rm \
    --mount "type=bind,src=${persisted_home},dst=/home/node" \
    "${IMAGE}" /bin/bash -lc \
      'grep -Fx "user_managed: true" /home/node/.goose/config/config.yaml >/dev/null'
fi

if [[ "${EXPECTED_RUNTIME}" == "kimi-code" ]]; then
  persisted_home="$(mktemp -d)"
  trap 'rm -rf "${persisted_home}"' EXIT
  chmod 0777 "${persisted_home}"

  docker run --rm \
    --mount "type=bind,src=${persisted_home},dst=/home/node" \
    "${IMAGE}" /bin/bash -lc '
      set -euo pipefail
      test -s /home/node/.kimi-code/tui.toml
      grep -F "auto_install = false" /home/node/.kimi-code/tui.toml >/dev/null
      test ! -e /home/node/.goose/config/config.yaml
      test ! -e /home/node/opencode.json
    '
  rm -f "${persisted_home}/.kimi-code/tui.toml"
  docker run --rm \
    --mount "type=bind,src=${persisted_home},dst=/home/node" \
    "${IMAGE}" /bin/bash -lc \
      'grep -F "auto_install = false" /home/node/.kimi-code/tui.toml >/dev/null'
fi

echo "${IMAGE}: ${EXPECTED_RUNTIME} image contract passed"
