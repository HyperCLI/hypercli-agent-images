from __future__ import annotations

import json
import sys
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import (  # noqa: E402
    assert_entrypoint_exit_passthrough,
    docker,
    image_config,
    require_image_argument,
)


image = require_image_argument()
config = image_config(image)
assert config.get("Entrypoint") == [
    "/usr/bin/tini",
    "--",
    "/usr/local/bin/hypercli-buzz-entrypoint",
]
assert config.get("WorkingDir") == "/home/node"
assert config.get("Cmd") == ["sleep", "infinity"]
env = dict(
    item.split("=", 1)
    for item in config.get("Env") or []
    if "=" in item
)
assert env.get("HOME") == "/home/node"
assert env.get("BUZZ_ACP_MCP_COMMAND", "") == ""
assert_entrypoint_exit_passthrough(image)

probe = r"""
import json
import os
import shutil
import subprocess
from pathlib import Path

tools = [
    "node",
    "npm",
    "python3",
    "pip3",
    "hyper",
    "git",
    "jq",
    "rg",
    "ssh",
    "sudo",
    "tini",
    "buzz",
    "buzz-acp",
    "buzz-dev-mcp",
]
print(json.dumps({
    "uid": os.getuid(),
    "sudo_user": subprocess.check_output(
        ["sudo", "-n", "whoami"],
        text=True,
    ).strip(),
    "tools": {tool: shutil.which(tool) for tool in tools},
    "buzz_commit": Path(
        "/opt/hypercli-buzz/.buzz-commit"
    ).read_text().strip(),
    "buzz_acp_is_symlink": Path("/usr/local/bin/buzz-acp").is_symlink(),
    "buzz_acp_help": subprocess.check_output(
        ["buzz-acp", "--help"],
        text=True,
        stderr=subprocess.STDOUT,
    ),
    "openclaw_binary": shutil.which("openclaw"),
    "openclaw_app": Path("/app/openclaw.mjs").exists(),
}))
"""
result = docker(
    "run",
    "--rm",
    "--entrypoint",
    "python3",
    image,
    "-c",
    probe,
)
payload = json.loads(result.stdout)
assert payload["uid"] == 1000
assert payload["sudo_user"] == "root"
assert all(payload["tools"].values()), payload["tools"]
assert len(payload["buzz_commit"]) == 40
assert payload["buzz_acp_is_symlink"] is False
assert "--text-mentions" in payload["buzz_acp_help"]
assert "--require-reply" in payload["buzz_acp_help"]
assert payload["openclaw_binary"] is None
assert payload["openclaw_app"] is False

print(f"{image}: Buzz base contract passed")
