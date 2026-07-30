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
    entrypoint="/usr/local/bin/hypercli-buzz-opencode-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/opencode",
    agent_args="acp",
    expected={"opencode-login"},
)

login_help = run(image, ["opencode", "auth", "login", "--help"]).stdout
assert "--provider" in login_help
assert "--method" in login_help
assert "0 credentials" in run(image, ["opencode", "auth", "list"]).stdout
assert_models(
    image,
    agent_command="/usr/local/bin/opencode",
    agent_args="acp",
)
assert_user_config_preserved(
    image,
    relative_path="opencode.json",
    generated_contains="kimi-k2.6-anthropic",
    user_content=json.dumps({"userManaged": True}) + "\n",
)

print(f"{image}: OpenCode contract passed")
