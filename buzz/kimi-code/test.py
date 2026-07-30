from __future__ import annotations

import sys
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import (  # noqa: E402
    assert_auth_methods,
    assert_common_contract,
    assert_user_config_preserved,
    require_image_argument,
    run,
)


image = require_image_argument()
assert_common_contract(
    image,
    runtime="kimi-code",
    agent_command="/usr/local/bin/kimi",
    agent_args="acp",
    entrypoint="/usr/local/bin/hypercli-buzz-kimi-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/kimi",
    agent_args="acp",
    expected={"login"},
)
run(image, ["kimi", "login", "--help"])
assert_user_config_preserved(
    image,
    relative_path=".kimi-code/tui.toml",
    generated_contains="auto_install = false",
    user_content="[upgrade]\nauto_install = true\n",
)

print(f"{image}: Kimi Code contract passed")
