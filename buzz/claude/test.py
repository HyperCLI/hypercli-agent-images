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
    require_image_argument,
    run,
)


image = require_image_argument()
assert_common_contract(
    image,
    runtime="claude-code",
    agent_command="/usr/local/bin/claude-agent-acp",
    agent_args="",
    mcp_command="",
    entrypoint="/usr/local/bin/hypercli-buzz-claude-entrypoint",
    claude_compatibility=True,
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/claude-agent-acp",
    agent_args="",
    expected={"claude-ai-login", "console-login"},
    terminal={"claude-ai-login", "console-login"},
)

claude_path = run(image, ["sh", "-lc", "command -v claude"]).stdout.strip()
assert claude_path == "/usr/local/bin/claude", claude_path

login_help = run(image, ["claude", "auth", "login", "--help"]).stdout
assert "--claudeai" in login_help
assert "--console" in login_help
assert "--sso" in login_help
status = run(image, ["claude", "auth", "status", "--json"], check=False)
assert status.returncode == 1
assert json.loads(status.stdout)["loggedIn"] is False
assert_models(
    image,
    agent_command="/usr/local/bin/claude-agent-acp",
    agent_args="",
)

print(f"{image}: Claude Code contract passed")
