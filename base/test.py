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
    "xsetroot": shutil.which("xsetroot"),
    "plank": shutil.which("plank"),
    "dconf": shutil.which("dconf"),
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
assert payload["xsetroot"]
assert payload["plank"]
assert payload["dconf"]
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

# Boolean-ish HYPER_PROXY_HOST selects the canonical in-cluster hyper-proxy
# endpoint (the provisioned alias of the cluster egress proxy).
for boolean_flag in ("true", "1", "TRUE", "yes", "on", "enabled"):
    alias_proxy = docker(
        "run",
        "--rm",
        "--entrypoint",
        "/bin/sh",
        image,
        "-c",
        launcher_probe,
        "sh",
        boolean_flag,
    ).stdout
    assert "--proxy-server=socks5://hyper-proxy:8080" in alias_proxy, (
        boolean_flag,
        alias_proxy,
    )
    assert "--proxy-server=true" not in alias_proxy, (boolean_flag, alias_proxy)

# Boolean-ish false HYPER_PROXY_HOST disables proxying instead of passing a
# nonsense URL through.
for false_flag in ("false", "0", "FALSE", "no", "off", "disabled"):
    no_proxy = docker(
        "run",
        "--rm",
        "--entrypoint",
        "/bin/sh",
        image,
        "-c",
        launcher_probe,
        "sh",
        false_flag,
    ).stdout
    assert "--proxy-server" not in no_proxy, (false_flag, no_proxy)

# --no-sandbox stays: agent pods are not guaranteed the kernel primitives
# Chrome's sandbox needs, and Chrome hard-refuses to launch when sandbox
# setup fails. The warning infobar it triggers is suppressed image-wide by
# the managed policy below, never by --test-type (which would flip broad
# automated-test behavior across Chrome).
assert "--no-sandbox" in without_proxy, without_proxy
assert "--test-type" not in without_proxy, without_proxy

# Managed Chrome policy disabling the "unsupported command-line flag"
# security-warning infobar that --no-sandbox would otherwise trigger in the
# agent desktop; this is the documented CommandLineFlagSecurityWarningsEnabled
# policy (local-state pref browser.command_line_flag_security_warnings_enabled).
chrome_policies = json.loads(
    docker(
        "run",
        "--rm",
        "--entrypoint",
        "cat",
        image,
        "/etc/opt/chrome/policies/managed/hypercli.json",
    ).stdout
)
assert chrome_policies == {"CommandLineFlagSecurityWarningsEnabled": False}, chrome_policies

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
assert "plank >>/tmp/plank.log 2>&1 &" in desktop_script
assert "hyper_configure_plank_dock" in desktop_script
assert ".config/plank/dock1/launchers" in desktop_script
assert "PlankDockItemPreferences" in desktop_script
assert "dconf write /net/launchpad/plank/docks/dock1/position" in desktop_script
assert "dconf write /net/launchpad/plank/docks/dock1/icon-size" in desktop_script
assert "/usr/local/bin/hypercli-chrome" in desktop_script
# Desktop bring-up defaults Chrome egress to the canonical in-cluster proxy,
# so the desktop path needs no client-side HYPER_PROXY_HOST toggle.
assert 'export HYPER_PROXY_HOST="${HYPER_PROXY_HOST:-true}"' in desktop_script
assert "feh --no-fehbg --bg-fill" in desktop_script
assert "/usr/local/share/hypercli/hypercli-bg.png" in desktop_script
assert "HYPER_DESKTOP_BACKGROUND_COLOR" in desktop_script

novnc_webroot = docker(
    "run",
    "--rm",
    "--entrypoint",
    "/bin/sh",
    image,
    "-c",
    "ls -l /usr/share/novnc/hyper-desktop.html /usr/share/novnc/core/rfb.js"
    " /usr/share/novnc/vnc.html /usr/share/novnc/vnc_auto.html"
    " /usr/local/lib/hypercli/pin-novnc-params.py"
    " /usr/local/lib/hypercli/stretch-novnc-display.py",
)
assert novnc_webroot.returncode == 0

# The stock full UI (vnc.html / vnc_auto.html) keeps serving, but its query
# string / hash / persisted settings can no longer redirect the RFB websocket
# or supply a password: the build-time patch pins host/port/path/password to
# the page-origin defaults. Anchors below are the exact patched strings; if
# the apt package changed shape, the image build itself already failed.
novnc_ui = docker(
    "run",
    "--rm",
    "--entrypoint",
    "cat",
    image,
    "/usr/share/novnc/app/ui.js",
).stdout
assert novnc_ui.count("hypercli-pinned-params") == 3
assert 'const HYPERCLI_PINNED_PARAMS = ["host", "port", "path", "password"];' in novnc_ui
assert "let val = HYPERCLI_PINNED_PARAMS.includes(name) ? null : WebUtil.getConfigVar(name);" in novnc_ui
assert "val = HYPERCLI_PINNED_PARAMS.includes(name) ? defVal : WebUtil.readSetting(name, defVal);" in novnc_ui
assert "let val = WebUtil.getConfigVar(name);" not in novnc_ui
assert "// Check Query string followed by cookie\n" not in novnc_ui
assert "password = WebUtil.getConfigVar('password');" not in novnc_ui

# noVNC Display stretch patch: autoscale() fills the container per axis
# instead of fit-letterboxing the fixed-geometry Xvfb desktop, and the
# pointer mapping every mouse/wheel/gesture path funnels through is per-axis
# so input stays aligned with the stretched canvas. Anchors below are the
# exact patched strings; if the apt package changed shape, the image build
# itself already failed in stretch-novnc-display.py.
novnc_display = docker(
    "run",
    "--rm",
    "--entrypoint",
    "cat",
    image,
    "/usr/share/novnc/core/display.js",
).stdout
assert novnc_display.count("hypercli-stretch-display") == 3
assert "this._scaleX = 1.0;" in novnc_display
assert "scaleRatioX = containerWidth / vp.w;" in novnc_display
assert "scaleRatioY = containerHeight / vp.h;" in novnc_display
assert "this._rescale(scaleRatioX, scaleRatioY);" in novnc_display
assert "_rescale(factorX, factorY)" in novnc_display
assert "factorX * vp.w + 'px'" in novnc_display
assert "factorY * vp.h + 'px'" in novnc_display
assert "x / this._scaleX + this._viewportLoc.x" in novnc_display
assert "y / this._scaleY + this._viewportLoc.y" in novnc_display
# Upstream's aspect-preserving fit (the letterboxing) is gone.
assert "fbAspectRatio" not in novnc_display
assert "x / this._scale + this._viewportLoc.x" not in novnc_display

desktop_viewer = docker(
    "run",
    "--rm",
    "--entrypoint",
    "cat",
    image,
    "/usr/share/novnc/hyper-desktop.html",
).stdout
assert "./core/rfb.js" in desktop_viewer
assert "hyper-desktop:ft-refresh" in desktop_viewer

# Reef-base allowlist (exfil guard for the `rh`/`ft` upload params). The rules
# live in `isAllowedReefBase`, a pure string-in/bool-out function kept free of
# DOM and network access so the exact rule set can be pinned here; these
# asserts are the in-repo unit coverage for it.
assert "function isAllowedReefBase(" in desktop_viewer
assert "host === String(pageHostname" in desktop_viewer
assert ".endsWith('.hypercli.app')" in desktop_viewer
assert ".endsWith('.hypercli.com')" in desktop_viewer
assert "'localhost'" in desktop_viewer
assert "'127.0.0.1'" in desktop_viewer
assert "uploadsBlocked" in desktop_viewer
assert "is not an allowed Reef host" in desktop_viewer
# Default Reef base still derives from the page host with "desktop-" stripped.
assert "window.location.hostname.replace(/^desktop-/, '')" in desktop_viewer

# noVNC security hardening on the custom viewer.
assert '<meta name="referrer" content="no-referrer">' in desktop_viewer
assert '<meta http-equiv="Content-Security-Policy"' in desktop_viewer
assert "script-src 'self' 'unsafe-inline'" in desktop_viewer
assert "connect-src 'self' wss: https:" in desktop_viewer
assert "history.replaceState(null, '', window.location.pathname)" in desktop_viewer
# Script-start scrub plus the post-connect/credentialsrequired/disconnect
# backstops.
assert desktop_viewer.count("scrubSensitiveUrlParams();") == 4
assert "rfb.scaleViewport = scaleViewport;" in desktop_viewer
# Scaling is the viewer default in our embed (the Display stretch patch
# means it fills instead of letterboxing); `scale=false` restores the fit.
assert "readQueryVariable('scale', 'true') !== 'false'" in desktop_viewer
assert "readQueryVariable('scale'" in desktop_viewer.split("scrubSensitiveUrlParams();")[0]
assert "clip-toast" in desktop_viewer
assert "navigator.clipboard.writeText(text).then(" in desktop_viewer
assert "execCommand" not in desktop_viewer
assert "<noscript>" in desktop_viewer

# Connected green dot: a CSS pseudo-element on #status, recolored by the
# .connected state class the RFB connect/disconnect listeners toggle (no dot
# glyph or color markup is baked into the status text itself).
assert "#status::before" in desktop_viewer
assert "#status.connected::before" in desktop_viewer
assert "classList.add('connected')" in desktop_viewer
assert "classList.remove('connected')" in desktop_viewer

vnc_lite = docker(
    "run",
    "--rm",
    "--entrypoint",
    "cat",
    image,
    "/usr/share/novnc/vnc_lite.html",
).stdout
assert '<meta name="referrer" content="no-referrer">' in vnc_lite
assert '<meta http-equiv="Content-Security-Policy"' in vnc_lite
assert "connect-src 'self' wss: https:" in vnc_lite
# Scrub at script start (after param capture) plus the post-connect backstop.
assert vnc_lite.count("history.replaceState(null, '', window.location.pathname);") == 2
assert "<noscript>" in vnc_lite

assert "--heartbeat 30" in desktop_script

print(f"{image}: HyperCLI agent base contract passed")
