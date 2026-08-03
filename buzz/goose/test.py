from __future__ import annotations

import sys
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import (  # noqa: E402
    assert_auth_methods,
    assert_common_contract,
    assert_models,
    assert_user_config_preserved,
    require_image_argument,
)


image = require_image_argument()
runtime_env = {
    "HYPER_AGENTS_API_KEY": "image-sanity-placeholder",
    "HYPER_AGENTS_API_BASE": "https://api.agents.example.invalid",
}
assert_common_contract(
    image,
    runtime="goose",
    agent_command="/usr/local/bin/goose",
    agent_args="acp",
    mcp_command="",
    entrypoint="/usr/local/bin/hypercli-buzz-goose-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/goose",
    agent_args="acp",
    expected={"goose-provider"},
    env=runtime_env,
)
assert_models(
    image,
    agent_command="/usr/local/bin/goose",
    agent_args="acp",
    env=runtime_env,
)
assert_user_config_preserved(
    image,
    relative_path=".goose/config/config.yaml",
    generated_contains="active_provider: hypercli",
    user_content="user_managed: true\n",
    env=runtime_env,
)
assert_user_config_preserved(
    image,
    relative_path=".goose/config/custom_providers/hypercli.json",
    generated_contains='"engine": "anthropic"',
    user_content='{"user_managed": true}\n',
    env=runtime_env,
)

print(f"{image}: Goose contract passed")
