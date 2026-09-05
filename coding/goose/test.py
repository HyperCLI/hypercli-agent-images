from __future__ import annotations

import sys
from pathlib import Path


BUZZ_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BUZZ_DIR))

from testlib import (  # noqa: E402
    assert_auth_methods,
    assert_common_contract,
    assert_models,
    assert_user_config_preserved,
    require_image_argument,
    run_python,
)


image = require_image_argument()
runtime_env = {
    "HYPER_AGENTS_API_KEY": "image-sanity-placeholder",
    "HYPER_AGENTS_API_BASE": "https://api.agents.example.invalid",
}
assert_common_contract(
    image,
    runtime="goose",
    agent_command="/usr/local/bin/goose",
    agent_args="acp",
    mcp_command="/usr/local/bin/buzz-dev-mcp",
    entrypoint="/usr/local/bin/hypercli-buzz-goose-entrypoint",
)
assert_auth_methods(
    image,
    agent_command="/usr/local/bin/goose",
    agent_args="acp",
    expected={"goose-provider"},
    env=runtime_env,
)
assert_models(
    image,
    agent_command="/usr/local/bin/goose",
    agent_args="acp",
    env=runtime_env,
)
provider_probe = """
import json
import os
from pathlib import Path

provider = json.loads(Path('/opt/hypercli-buzz/goose-provider.json').read_text())
models = {model['name']: model for model in provider['models']}
config_text = Path('/opt/hypercli-buzz/goose-config.yaml').read_text()
print(json.dumps({
    'model_names': sorted(models),
    'context_limits': {name: model.get('context_limit') for name, model in models.items()},
    'reasoning': {name: model.get('reasoning') for name, model in models.items()},
    'config_text': config_text,
    'mcp_command': os.environ.get('BUZZ_ACP_MCP_COMMAND'),
    'model_prefix': os.environ.get('BUZZ_MODEL_PREFIX'),
    'goose_skill_link': os.readlink('/home/node/.buzz/.goose/skills/hypercli'),
}))
"""
provider_contract = run_python(image, provider_probe, env=runtime_env)
assert provider_contract["model_names"] == [
    "coding",
    "coding-anthropic",
    "default",
    "default-anthropic",
    "kimi-k2.5",
    "kimi-k2.5-anthropic",
    "kimi-k2.6",
    "kimi-k2.6-anthropic",
    "kimi-k3",
    "kimi-k3-anthropic",
]
assert set(provider_contract["context_limits"].values()) == {262144}
assert set(provider_contract["reasoning"].values()) == {True}
config_text = provider_contract["config_text"]
for expected_config in [
    "active_provider: hypercli",
    "model: coding-anthropic",
    "  developer:",
    "    type: builtin",
    "  memory:",
    "  skills:",
    "    type: platform",
]:
    assert expected_config in config_text, config_text
assert provider_contract["mcp_command"] == "/usr/local/bin/buzz-dev-mcp"
assert provider_contract["model_prefix"] is None
assert provider_contract["goose_skill_link"] == "../../.agents/skills/hypercli"
assert_user_config_preserved(
    image,
    relative_path=".goose/config/config.yaml",
    generated_contains="active_provider: hypercli",
    user_content="user_managed: true\n",
    env=runtime_env,
)
assert_user_config_preserved(
    image,
    relative_path=".goose/config/custom_providers/hypercli.json",
    generated_contains='"engine": "anthropic"',
    user_content='{"user_managed": true}\n',
    env=runtime_env,
)

print(f"{image}: Goose contract passed")
