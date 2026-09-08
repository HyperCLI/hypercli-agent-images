from __future__ import annotations

import json
import sys
from pathlib import Path


IMAGE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IMAGE_DIR / "coding"))

from testlib import docker, image_config, require_image_argument  # noqa: E402


image = require_image_argument()
config = image_config(image)
assert config.get("WorkingDir") == "/home/node"
env = dict(item.split("=", 1) for item in config.get("Env") or [] if "=" in item)
assert env.get("HOME") == "/home/node"
assert env.get("CHROME_EXECUTABLE_PATH") == "/usr/local/bin/hypercli-chrome"
assert env.get("PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH") == "/usr/local/bin/hypercli-chrome"
assert "CODING_AGENT_STATE_DIR" not in env
assert "CODING_AGENT_WORKSPACE_DIR" not in env
assert not (env.get("PATH") or "").startswith("/opt/hypercli-cli/venv/bin:")

probe = r"""
import json
import os
import shutil
import subprocess
from pathlib import Path

print(json.dumps({
    "uid": os.getuid(),
    "sudo_user": subprocess.check_output(["sudo", "-n", "whoami"], text=True).strip(),
    "hyper": shutil.which("hyper"),
    "hyper_target": os.path.realpath(shutil.which("hyper") or ""),
    "skills": bool(list(Path("/opt/hypercli/skills").glob("*/SKILL.md"))),
    "hyper_acp": shutil.which("hyper-acp"),
    "buzz": shutil.which("buzz"),
    "openclaw": shutil.which("openclaw"),
}))
"""
result = docker("run", "--rm", "--entrypoint", "python3", image, "-c", probe)
payload = json.loads(result.stdout)
assert payload["uid"] == 1000
assert payload["sudo_user"] == "root"
assert payload["hyper"]
assert payload["hyper_target"] == "/opt/hypercli-cli/venv/bin/hyper"
assert payload["skills"] is True
assert payload["hyper_acp"] is None
assert payload["buzz"] is None
assert payload["openclaw"] is None

launcher_probe = r"""
set -eu
cat >/tmp/fake-chrome <<'EOF'
#!/bin/sh
printf '%s\n' "$@"
EOF
chmod 0755 /tmp/fake-chrome
export HYPERCLI_CHROME_BIN=/tmp/fake-chrome
if [ -n "${1:-}" ]; then
  export HYPER_PROXY_HOST="$1"
fi
exec /usr/local/bin/hypercli-chrome https://example.test
"""

without_proxy = docker(
    "run",
    "--rm",
    "--entrypoint",
    "/bin/sh",
    image,
    "-c",
    launcher_probe,
    "sh",
).stdout
assert "--proxy-server" not in without_proxy, without_proxy
assert "--user-data-dir=/home/node/.config/google-chrome" in without_proxy

with_proxy = docker(
    "run",
    "--rm",
    "--entrypoint",
    "/bin/sh",
    image,
    "-c",
    launcher_probe,
    "sh",
    "socks5://127.0.0.1:8080",
).stdout
assert "--proxy-server=socks5://127.0.0.1:8080" in with_proxy, with_proxy

desktop_entry = docker(
    "run",
    "--rm",
    "--entrypoint",
    "cat",
    image,
    "/usr/share/applications/google-chrome.desktop",
).stdout
assert "Exec=/usr/local/bin/hypercli-chrome %U" in desktop_entry
assert "Exec=google-chrome-stable" not in desktop_entry

print(f"{image}: HyperCLI agent base contract passed")
