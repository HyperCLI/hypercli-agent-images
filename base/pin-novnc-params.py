#!/usr/bin/env python3
"""Pin the vendored noVNC full UI to its page-origin connection defaults.

The stock noVNC 1.3 full UI (`vnc.html`, `vnc_auto.html` -> `app/ui.js`) lets
the URL query string or hash override the RFB websocket target (`host`,
`port`, `path`) and even the VNC password (`password`), and additionally
honours values persisted in localStorage via `WebUtil.readSetting`. Inside
the agent desktop webroot the websocket must always point back at the local
websockify instance that is serving the page, so this script rewrites the
two sinks in `app/ui.js`:

* `initSetting()`: for the pinned names, ignore the URL query/hash and any
  persisted setting and keep the caller-provided default
  (`window.location.hostname`, the page port, `websockify`), and
* `connect()`: never read a `password` from the URL.

`vnc_lite.html` and `hyper-desktop.html` are self-contained (they do not
import `app/ui.js`) and are intentionally unaffected.

Every edit is anchored on an exact string from the vendored file; if the
package no longer matches, the script fails and the image build stops
instead of silently shipping the unpatched page.
"""

from __future__ import annotations

import sys
from pathlib import Path


PINNED_MARKER = "hypercli-pinned-params"

PINNED_CONSTANT_ANCHOR = 'import * as WebUtil from "./webutil.js";'
PINNED_CONSTANT = (
    PINNED_CONSTANT_ANCHOR
    + """

// hypercli-pinned-params (build-time patch, base/pin-novnc-params.py): the
// RFB connection target and VNC password must not be overridable from the
// URL or from persisted settings; they stay pinned to the page defaults.
const HYPERCLI_PINNED_PARAMS = ["host", "port", "path", "password"];"""
)

INIT_SETTING_ANCHOR = """        // Check Query string followed by cookie
        let val = WebUtil.getConfigVar(name);
        if (val === null) {
            val = WebUtil.readSetting(name, defVal);
        }"""
INIT_SETTING_PATCHED = """        // Check Query string followed by cookie.
        // hypercli-pinned-params: the pinned names keep the caller-provided
        // defaults; URL query/hash and persisted storage cannot override them.
        let val = HYPERCLI_PINNED_PARAMS.includes(name) ? null : WebUtil.getConfigVar(name);
        if (val === null) {
            val = HYPERCLI_PINNED_PARAMS.includes(name) ? defVal : WebUtil.readSetting(name, defVal);
        }"""

PASSWORD_ANCHOR = """        if (typeof password === 'undefined') {
            password = WebUtil.getConfigVar('password');
            UI.reconnectPassword = password;
        }"""
PASSWORD_PATCHED = """        if (typeof password === 'undefined') {
            // hypercli-pinned-params: never accept a VNC password from the URL.
            password = null;
            UI.reconnectPassword = password;
        }"""

REPLACEMENTS = (
    (PINNED_CONSTANT_ANCHOR, PINNED_CONSTANT),
    (INIT_SETTING_ANCHOR, INIT_SETTING_PATCHED),
    (PASSWORD_ANCHOR, PASSWORD_PATCHED),
)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} NOVNC_WEBROOT")
    webroot = Path(sys.argv[1])
    ui_js = webroot / "app" / "ui.js"
    text = ui_js.read_text(encoding="utf-8")
    if PINNED_MARKER in text:
        raise SystemExit(f"{ui_js} is already patched")
    for anchor, patched in REPLACEMENTS:
        count = text.count(anchor)
        if count != 1:
            raise SystemExit(
                f"{ui_js}: expected exactly 1 anchor match, found {count}:\n{anchor}"
            )
        text = text.replace(anchor, patched, 1)
    for anchor, _ in REPLACEMENTS:
        if anchor == PINNED_CONSTANT_ANCHOR:
            continue
        if anchor in text:
            raise SystemExit(f"{ui_js}: anchor survived patching:\n{anchor}")
    if text.count(PINNED_MARKER) != 3:
        raise SystemExit(f"{ui_js}: patch marker count mismatch after patching")
    ui_js.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
