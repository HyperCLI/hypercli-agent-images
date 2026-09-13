#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def main() -> int:
    managed_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/run/hypercli-hermes-managed")
    managed_dir.mkdir(parents=True, exist_ok=True)
    run(sys.executable, str(SCRIPT_DIR / "env.py"), str(managed_dir / ".env"))
    run(sys.executable, str(SCRIPT_DIR / "models.py"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
