from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import docker, image_config, require_image_argument  # noqa: E402


image = require_image_argument()
config = image_config(image)
assert config.get("Entrypoint") == [
    "/usr/bin/tini",
    "--",
    "/usr/local/bin/hypercli-buzz-entrypoint",
]
assert config.get("WorkingDir") == "/home/node"
assert config.get("Cmd") == ["sleep", "infinity"]

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
    "hypercli_ref": Path(
        "/opt/hypercli/.baked-ref"
    ).read_text().strip(),
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
assert len(payload["hypercli_ref"]) == 40
assert payload["openclaw_binary"] is None
assert payload["openclaw_app"] is False

print(f"{image}: Buzz base contract passed")
