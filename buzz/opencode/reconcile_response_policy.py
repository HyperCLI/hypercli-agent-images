#!/usr/bin/env python3
"""Reconcile the hosted OpenCode reply policy into the persisted Buzz nest."""

from __future__ import annotations

import os
import re
from pathlib import Path


START = "<!-- BEGIN HYPERCLI BUZZ OPENCODE RESPONSE POLICY — managed automatically -->"
END = "<!-- END HYPERCLI BUZZ OPENCODE RESPONSE POLICY — managed automatically -->"
POLICY = Path("/opt/hypercli-buzz/opencode/response-policy.md")
TARGET = Path("/home/node/.buzz/AGENTS.md")


def main() -> None:
    policy = POLICY.read_text(encoding="utf-8").strip()
    if not policy.startswith(START) or not policy.endswith(END):
        raise RuntimeError(f"invalid managed response policy: {POLICY}")
    if TARGET.is_symlink():
        raise RuntimeError(f"refusing symlinked Buzz instructions: {TARGET}")

    current = TARGET.read_text(encoding="utf-8")
    managed = re.compile(
        rf"{re.escape(START)}.*?{re.escape(END)}",
        flags=re.DOTALL,
    )
    unmanaged = managed.sub("", current)
    if START in unmanaged or END in unmanaged:
        raise RuntimeError(f"malformed managed response policy in {TARGET}")

    reconciled = f"{unmanaged.rstrip()}\n\n{policy}\n"
    if reconciled == current:
        return

    temporary = TARGET.with_name(f".{TARGET.name}.hypercli.tmp")
    temporary.write_text(reconciled, encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, TARGET)


if __name__ == "__main__":
    main()
