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
    run,
)


image = require_image_argument()
assert_common_contract(
    image,
    runtime="kimi-code",
    agent_command="/usr/local/bin/kimi",
    agent_args="acp",
    mcp_command="",
    entrypoint="/usr/local/bin/hypercli-buzz-kimi-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/kimi",
    agent_args="acp",
    expected={"login"},
    terminal={"login"},
)
run(image, ["kimi", "login", "--help"])
runtime_env = {
    "BUZZ_ACP_MODEL": "runtime-model",
    "HYPER_API_BASE": "https://api.dev.hypercli.com/",
    "HYPER_AGENTS_API_KEY": "runtime-secret",
}
configured = run(
    image,
    [
        "python3",
        "-c",
        """
from pathlib import Path

config = Path('/home/node/.kimi-code/config.toml')
assert not config.exists()
""",
    ],
    env=runtime_env,
)
assert configured.returncode == 0
assert_models(
    image,
    agent_command="/usr/local/bin/kimi",
    agent_args="acp",
    env=runtime_env,
)
run(image, ["kimi", "doctor"], env=runtime_env)
assert_user_config_preserved(
    image,
    relative_path=".kimi-code/tui.toml",
    generated_contains="auto_install = false",
    user_content="[upgrade]\nauto_install = true\n",
)

print(f"{image}: Kimi Code contract passed")
