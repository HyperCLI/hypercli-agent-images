from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import (  # noqa: E402
    assert_auth_methods,
    assert_common_contract,
    assert_models,
    require_image_argument,
    run,
)


image = require_image_argument()
assert_common_contract(
    image,
    runtime="codex",
    agent_command="/usr/local/bin/codex-acp",
    agent_args="",
    entrypoint="/usr/local/bin/hypercli-buzz-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/codex-acp",
    agent_args="",
    expected={"api-key"},
)

assert "--device-auth" in run(image, ["codex", "login", "--help"]).stdout
status = run(image, ["codex", "login", "status"], check=False)
assert status.returncode == 1
assert "Not logged in" in status.stdout + status.stderr

with tempfile.TemporaryDirectory() as home_name:
    home = Path(home_name)
    home.chmod(0o777)
    auth_dir = home / ".codex"
    auth_dir.mkdir()
    (auth_dir / "auth.json").write_text(
        json.dumps({"OPENAI_API_KEY": "image-sanity-placeholder"}) + "\n",
        encoding="utf-8",
    )
    assert_models(
        image,
        agent_command="/usr/local/bin/codex-acp",
        agent_args="",
        mounts=[(home, "/home/node")],
    )

print(f"{image}: Codex contract passed")
