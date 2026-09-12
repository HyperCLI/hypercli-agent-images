"""Harden the upstream noVNC vnc_lite.html installed by the Debian novnc package.

Anchored string surgery applied at image build time. Each upstream anchor must
match exactly once so a packaged noVNC update that drifts from these anchors
fails the build loudly instead of shipping a silently unhardened page.
"""

from __future__ import annotations

import sys
from pathlib import Path

VNC_LITE = Path("/usr/share/novnc/vnc_lite.html")

CHARSET_META = '    <meta charset="utf-8">'

CONNECT_HANDLER = (
    "        function connectedToServer(e) {\n"
    '            status("Connected to " + desktopName);\n'
    "        }"
)

BODY_TAG = "<body>"

REFERRER_META = '    <meta name="referrer" content="no-referrer">'

# Build is not guaranteed to run on a pristine webroot; refuse to patch a page
# that already carries the hardening markers (same guard as
# pin-novnc-params.py).
PATCHED_MARKER = 'name="referrer" content="no-referrer"'

# script-src keeps 'unsafe-inline': the upstream page ships an inline module
# script, which is also what the token scrub below hooks into.
CSP_META = (
    '    <meta http-equiv="Content-Security-Policy" content="'
    "default-src 'self'; script-src 'self' 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
    "connect-src 'self' wss: https:"
    '">'
)

SCRUB_CALL = (
    '            status("Connected to " + desktopName);\n'
    "            // The ?token= was captured when the ws URL was built above;\n"
    "            // drop it from the visible URL once connected.\n"
    "            history.replaceState(null, '', window.location.pathname);"
)

PARAM_TAIL = (
    "        // Set parameters that can be changed on an active connection\n"
    "        rfb.viewOnly = readQueryVariable('view_only', false);\n"
    "        rfb.scaleViewport = readQueryVariable('scale', false);"
)

EARLY_SCRUB = (
    PARAM_TAIL + "\n"
    "        // All params are captured; scrub secrets out of the visible URL\n"
    "        // immediately instead of waiting for the connect event.\n"
    "        history.replaceState(null, '', window.location.pathname);"
)

NOSCRIPT = (
    "<body>\n"
    '    <noscript><div style="padding:8px;font:bold 12px Helvetica,Arial,sans-serif">'
    "noVNC requires JavaScript to reach this desktop.</div></noscript>"
)


def main() -> int:
    text = VNC_LITE.read_text(encoding="utf-8")
    if PATCHED_MARKER in text:
        raise SystemExit(f"{VNC_LITE} is already patched")
    anchors = (CHARSET_META, CONNECT_HANDLER, PARAM_TAIL, BODY_TAG)
    for anchor in anchors:
        if text.count(anchor) != 1:
            print(
                f"vnc_lite.html anchor drifted (count={text.count(anchor)}): {anchor!r}",
                file=sys.stderr,
            )
            return 1

    text = text.replace(
        CHARSET_META, f"{CHARSET_META}\n\n{REFERRER_META}\n\n{CSP_META}"
    )
    text = text.replace(
        CONNECT_HANDLER,
        CONNECT_HANDLER.replace(
            '            status("Connected to " + desktopName);', SCRUB_CALL
        ),
    )
    text = text.replace(PARAM_TAIL, EARLY_SCRUB)
    text = text.replace(BODY_TAG, NOSCRIPT)
    VNC_LITE.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
