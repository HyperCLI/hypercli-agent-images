from __future__ import annotations

import json
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
    run,
)


image = require_image_argument()
assert_common_contract(
    image,
    runtime="opencode",
    agent_command="/usr/local/bin/opencode",
    agent_args="acp",
    mcp_command="",
    entrypoint="/usr/local/bin/hypercli-buzz-opencode-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/opencode",
    agent_args="acp",
    expected={"opencode-login"},
    terminal={"opencode-login"},
)

login_result = run(image, ["opencode", "auth", "login", "--help"])
login_help = login_result.stdout + login_result.stderr
assert "--provider" in login_help
assert "--method" in login_help
list_result = run(image, ["opencode", "auth", "list"])
assert "0 credentials" in list_result.stdout + list_result.stderr
assert_models(
    image,
    agent_command="/usr/local/bin/opencode",
    agent_args="acp",
)
assert_user_config_preserved(
    image,
    relative_path=".config/opencode/opencode.json",
    generated_contains="coding-anthropic",
    user_content=json.dumps({"userManaged": True}) + "\n",
)

print(f"{image}: OpenCode contract passed")
