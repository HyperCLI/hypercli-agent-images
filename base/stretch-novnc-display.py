#!/usr/bin/env python3
"""Make the vendored noVNC Display fill its container exactly.

Anchored string surgery applied at image build time, in the spirit of
base/patch_vnc_lite.py and base/pin-novnc-params.py: every upstream anchor
must match exactly once, so a packaged noVNC update that drifts from these
anchors fails the build loudly instead of silently shipping the fit-letterbox
behavior (or a half-applied patch).

Context: upstream `Display.autoscale()` fits the remote framebuffer *inside*
the container while preserving aspect ratio (the smaller of the two ratios),
which leaves pillar/letterbox bars whenever the viewer's aspect differs from
the fixed Xvfb geometry (HYPER_DESKTOP_GEOMETRY, 1280x800x24). The remote
resize alternative (RFB `resizeSession`/ExtendedDesktopSize) is unavailable:
x11vnc 0.9.16 does not act on client SetDesktopSize, and Xvfb caps its RANDR
range at the initial geometry. This patch therefore:

* adds per-axis scale factors (`_scaleX`/`_scaleY`) to Display,
* stretches `autoscale()` to each container dimension independently (the
  "fill" behavior the HyperCLI desktop viewer wants), and
* updates `absX()`/`absY()` (the coordinate mapping every pointer, wheel,
  and gesture path funnels through) so mouse and touch stay aligned with the
  stretched canvas.

The patch is applied to the packaged /usr/share/novnc/core/display.js. In-repo
checks live in base/test.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

DISPLAY_JS = Path("/usr/share/novnc/core/display.js")

MARKER = "hypercli-stretch-display"

# Refuse to patch a webroot that already carries the stretch (same guard
# as patch_vnc_lite.py / pin-novnc-params.py).
SCALE_MEMBER_ANCHOR = "        this._scale = 1.0;"
SCALE_MEMBER_PATCHED = (
    "// "
    + MARKER
    + """ (build-time patch, base/stretch-novnc-display.py): per-axis scale
    // factors so autoscale() fills the container instead of fit-letterboxing.
    this._scaleX = 1.0;
    this._scaleY = 1.0;
    this._scale = 1.0;"""
)

AUTOSCALE_ANCHOR = """    autoscale(containerWidth, containerHeight) {
        let scaleRatio;

        if (containerWidth === 0 || containerHeight === 0) {
            scaleRatio = 0;

        } else {

            const vp = this._viewportLoc;
            const targetAspectRatio = containerWidth / containerHeight;
            const fbAspectRatio = vp.w / vp.h;

            if (fbAspectRatio >= targetAspectRatio) {
                scaleRatio = containerWidth / vp.w;
            } else {
                scaleRatio = containerHeight / vp.h;
            }
        }

        this._rescale(scaleRatio);
    }"""

AUTOSCALE_PATCHED = """    autoscale(containerWidth, containerHeight) {
        let scaleRatioX;
        let scaleRatioY;

        if (containerWidth === 0 || containerHeight === 0) {
            scaleRatioX = 0;
            scaleRatioY = 0;

        } else {

            // """ + MARKER + """: stretch each axis to fill the container.
            // The embed always renders the fixed-geometry Xvfb desktop and
            // should fill the viewer rather than letterbox.
            const vp = this._viewportLoc;

            scaleRatioX = containerWidth / vp.w;
            scaleRatioY = containerHeight / vp.h;
        }

        this._rescale(scaleRatioX, scaleRatioY);
    }"""

RESCALE_ANCHOR = """    _rescale(factor) {
        this._scale = factor;
        const vp = this._viewportLoc;

        // NB(directxman12): If you set the width directly, or set the
        //                   style width to a number, the canvas is cleared.
        //                   However, if you set the style width to a string
        //                   ('NNNpx'), the canvas is scaled without clearing.
        const width = factor * vp.w + 'px';
        const height = factor * vp.h + 'px';

        if ((this._target.style.width !== width) ||
            (this._target.style.height !== height)) {
            this._target.style.width = width;
            this._target.style.height = height;
        }
    }"""

RESCALE_PATCHED = """    _rescale(factorX, factorY) {
        // """ + MARKER + """: a single argument still rescales uniformly
        // (viewport changes, `display.scale =` re-flows).
        if (factorY === undefined) {
            factorY = factorX;
        }
        this._scaleX = factorX;
        this._scaleY = factorY;
        this._scale = Math.min(factorX, factorY);
        const vp = this._viewportLoc;

        // NB(directxman12): If you set the width directly, or set the
        //                   style width to a number, the canvas is cleared.
        //                   However, if you set the style width to a string
        //                   ('NNNpx'), the canvas is scaled without clearing.
        const width = factorX * vp.w + 'px';
        const height = factorY * vp.h + 'px';

        if ((this._target.style.width !== width) ||
            (this._target.style.height !== height)) {
            this._target.style.width = width;
            this._target.style.height = height;
        }
    }"""

ABSX_ANCHOR = """    absX(x) {
        if (this._scale === 0) {
            return 0;
        }
        return toSigned32bit(x / this._scale + this._viewportLoc.x);
    }"""

ABSX_PATCHED = """    absX(x) {
        if (this._scaleX === 0) {
            return 0;
        }
        return toSigned32bit(x / this._scaleX + this._viewportLoc.x);
    }"""

ABSY_ANCHOR = """    absY(y) {
        if (this._scale === 0) {
            return 0;
        }
        return toSigned32bit(y / this._scale + this._viewportLoc.y);
    }"""

ABSY_PATCHED = """    absY(y) {
        if (this._scaleY === 0) {
            return 0;
        }
        return toSigned32bit(y / this._scaleY + this._viewportLoc.y);
    }"""

REPLACEMENTS = (
    (SCALE_MEMBER_ANCHOR, SCALE_MEMBER_PATCHED),
    (AUTOSCALE_ANCHOR, AUTOSCALE_PATCHED),
    (RESCALE_ANCHOR, RESCALE_PATCHED),
    (ABSX_ANCHOR, ABSX_PATCHED),
    (ABSY_ANCHOR, ABSY_PATCHED),
)


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} NOVNC_WEBROOT")
    display_js = Path(sys.argv[1]) / "core" / "display.js"
    text = display_js.read_text(encoding="utf-8")
    if MARKER in text:
        raise SystemExit(f"{display_js} is already patched")
    for anchor, patched in REPLACEMENTS:
        count = text.count(anchor)
        if count != 1:
            raise SystemExit(
                f"{display_js}: expected exactly 1 anchor match, found {count}:\n{anchor}"
            )
        text = text.replace(anchor, patched, 1)
    for anchor, _ in REPLACEMENTS:
        if anchor in text:
            raise SystemExit(f"{display_js}: anchor survived patching:\n{anchor}")
    if text.count(MARKER) != 3:
        raise SystemExit(f"{display_js}: patch marker count mismatch after patching")
    display_js.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
