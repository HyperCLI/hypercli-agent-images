from __future__ import annotations

import sys
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import (  # noqa: E402
    assert_auth_methods,
    assert_common_contract,
    assert_models,
    require_image_argument,
    run_python,
)


image = require_image_argument()
runtime_env = {
    "HYPER_AGENTS_API_KEY": "image-sanity-placeholder",
    "HYPER_API_BASE": "https://api.example.invalid",
}
assert_common_contract(
    image,
    runtime="buzz-agent",
    agent_command="/usr/local/bin/buzz-agent",
    agent_args="",
    mcp_command="/usr/local/bin/buzz-dev-mcp",
    entrypoint="/usr/local/bin/hypercli-buzz-agent-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/buzz-agent",
    agent_args="",
    expected=set(),
    env=runtime_env,
)
models = assert_models(
    image,
    agent_command="/usr/local/bin/buzz-agent",
    agent_args="",
    env=runtime_env,
)
assert models["agent"]["name"] == "buzz-agent", models

env_probe = """
import json
import os
print(json.dumps({
    key: os.environ.get(key)
    for key in (
        "BUZZ_AGENT_PROVIDER",
        "BUZZ_AGENT_MODEL",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_API_KEY",
    )
}))
"""
defaults = run_python(image, env_probe, env=runtime_env)
assert defaults == {
    "BUZZ_AGENT_PROVIDER": "anthropic",
    "BUZZ_AGENT_MODEL": "kimi-k2.6-anthropic",
    "ANTHROPIC_BASE_URL": "https://api.example.invalid",
    "ANTHROPIC_API_KEY": "image-sanity-placeholder",
}

overrides = {
    **runtime_env,
    "BUZZ_AGENT_PROVIDER": "openai",
    "BUZZ_AGENT_MODEL": "user-model",
    "ANTHROPIC_BASE_URL": "",
    "ANTHROPIC_API_KEY": "user-key",
}
preserved = run_python(image, env_probe, env=overrides)
assert preserved == {
    "BUZZ_AGENT_PROVIDER": "openai",
    "BUZZ_AGENT_MODEL": "user-model",
    "ANTHROPIC_BASE_URL": "",
    "ANTHROPIC_API_KEY": "user-key",
}

print(f"{image}: native Buzz Agent contract passed")
