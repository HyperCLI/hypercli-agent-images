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
    "hyper_version": subprocess.check_output(["hyper", "--version"], text=True).strip(),
    "hyper_help": subprocess.run(["hyper", "--help"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode,
    "hypercli_dirs": sorted(path.name for path in Path("/opt/hypercli").iterdir()),
    "corepack": shutil.which("corepack"),
    "pnpm": shutil.which("pnpm"),
    "yarn": shutil.which("yarn"),
    "feh": shutil.which("feh"),
    "background": Path("/usr/local/share/hypercli/hypercli-bg.png").is_file(),
    "fonts": {
        name: subprocess.check_output(["fc-match", name], text=True).split(":", 1)[0]
        for name in ("Noto Sans", "Noto Color Emoji", "Noto Sans CJK SC", "Fira Code")
    },
    "skills": bool(list(Path("/opt/hypercli/skills").glob("*/SKILL.md"))),
    "acp": shutil.which("acp"),
    "buzz": shutil.which("buzz"),
    "openclaw": shutil.which("openclaw"),
}))
"""
result = docker("run", "--rm", "--entrypoint", "python3", image, "-c", probe)
payload = json.loads(result.stdout)
assert payload["uid"] == 1000
assert payload["sudo_user"] == "root"
assert payload["hyper"]
assert payload["hyper_target"] == "/opt/hypercli/cli/dist/index.js"
assert payload["hyper_version"].startswith("hyper ")
assert payload["hyper_help"] == 0
assert payload["hypercli_dirs"] == ["cli", "docs", "skills", "ts-sdk"]
assert payload["corepack"]
assert payload["pnpm"]
assert payload["yarn"]
assert payload["feh"]
assert payload["background"] is True
assert payload["fonts"] == {
    "Noto Sans": "NotoSans-Regular.ttf",
    "Noto Color Emoji": "NotoColorEmoji.ttf",
    "Noto Sans CJK SC": "NotoSansCJK-Regular.ttc",
    "Fira Code": "FiraCode-Regular.ttf",
}
assert payload["skills"] is True
assert payload["acp"] is None
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

desktop_shortcut = docker(
    "run",
    "--rm",
    "--entrypoint",
    "/bin/sh",
    image,
    "-c",
    "test ! -e /home/node/Desktop/google-chrome.desktop",
)
assert desktop_shortcut.returncode == 0

desktop_script = docker(
    "run",
    "--rm",
    "--entrypoint",
    "cat",
    image,
    "/usr/local/lib/hypercli/desktop.sh",
).stdout
assert "xfce4-panel" not in desktop_script
assert "hyper_configure_xfce_panel" not in desktop_script
assert "hyper_apply_xfce_panel" not in desktop_script
assert "feh --no-fehbg --bg-fill" in desktop_script
assert "/usr/local/share/hypercli/hypercli-bg.png" in desktop_script
assert "HYPER_DESKTOP_BACKGROUND_COLOR" in desktop_script

print(f"{image}: HyperCLI agent base contract passed")
