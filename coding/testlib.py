from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any


WORKSPACE = Path("/home/node")
WORKSPACES = Path("/home/node/shared")
STATE_DIR = Path("/home/node/.coding-agent")
ENTRYPOINT_EXIT_CODE = 42
ENTRYPOINT_EXIT_TIMEOUT_SECONDS = 30


def require_image_argument() -> str:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} IMAGE")
    return sys.argv[1]


def docker(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["docker", *args],
        check=False,
        text=True,
        capture_output=True,
    )
    if check and result.returncode != 0:
        raise AssertionError(
            f"docker {' '.join(args)} failed with {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def image_config(image: str) -> dict[str, Any]:
    result = docker("image", "inspect", "--format", "{{json .Config}}", image)
    payload = json.loads(result.stdout)
    assert isinstance(payload, dict)
    return payload


def assert_entrypoint_exit_passthrough(image: str) -> None:
    """Prove the real image entrypoint terminates with its child process."""
    container_name = f"hypercli-coding-entrypoint-exit-{uuid.uuid4().hex}"
    docker(
        "create",
        "--name",
        container_name,
        "--network",
        "none",
        image,
        "python3",
        "-c",
        f"raise SystemExit({ENTRYPOINT_EXIT_CODE})",
    )
    try:
        docker("start", container_name)
        try:
            waited = subprocess.run(
                ["docker", "wait", container_name],
                check=False,
                text=True,
                capture_output=True,
                timeout=ENTRYPOINT_EXIT_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise AssertionError(
                f"{image}: real entrypoint did not exit within "
                f"{ENTRYPOINT_EXIT_TIMEOUT_SECONDS}s"
            ) from exc
        assert waited.returncode == 0, (
            f"docker wait failed with {waited.returncode}\n"
            f"stdout:\n{waited.stdout}\nstderr:\n{waited.stderr}"
        )
        assert waited.stdout.strip() == str(ENTRYPOINT_EXIT_CODE), (
            f"{image}: expected entrypoint exit {ENTRYPOINT_EXIT_CODE}, "
            f"got {waited.stdout.strip()!r}"
        )
    finally:
        cleanup = docker("rm", "--force", container_name, check=False)
        if cleanup.returncode != 0:
            raise AssertionError(
                f"could not remove entrypoint probe container {container_name}\n"
                f"stdout:\n{cleanup.stdout}\nstderr:\n{cleanup.stderr}"
            )


def run(
    image: str,
    command: list[str],
    *,
    env: dict[str, str] | None = None,
    mounts: list[tuple[Path, str]] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    args = ["run", "--rm", "--network", "none"]
    for key, value in (env or {}).items():
        args.extend(["--env", f"{key}={value}"])
    for source, destination in mounts or []:
        args.extend(["--mount", f"type=bind,src={source},dst={destination}"])
    args.extend([image, *command])
    return docker(*args, check=check)


def run_json(
    image: str,
    command: list[str],
    *,
    env: dict[str, str] | None = None,
    mounts: list[tuple[Path, str]] | None = None,
) -> dict[str, Any]:
    result = run(image, command, env=env, mounts=mounts)
    payload = json.loads(result.stdout)
    assert isinstance(payload, dict), payload
    return payload


def run_python(
    image: str,
    source: str,
    *,
    env: dict[str, str] | None = None,
    mounts: list[tuple[Path, str]] | None = None,
) -> dict[str, Any]:
    return run_json(image, ["python3", "-c", source], env=env, mounts=mounts)


def acp_command(
    operation: str,
    *,
    agent_command: str,
    agent_args: str,
) -> list[str]:
    command = [
        "acp",
        "plugin",
        "buzz",
        operation,
        "--agent-command",
        agent_command,
    ]
    if agent_args:
        command.extend(["--agent-args", agent_args])
    command.append("--json")
    return command


def assert_auth_methods(
    image: str,
    *,
    agent_command: str,
    agent_args: str,
    expected: set[str],
    terminal: set[str] | None = None,
    env: dict[str, str] | None = None,
) -> None:
    payload = run_json(
        image,
        acp_command(
            "auth-methods",
            agent_command=agent_command,
            agent_args=agent_args,
        ),
        env=env,
    )
    methods = payload.get("methods")
    assert isinstance(methods, list), payload
    methods_by_id = {
        method["id"]: method
        for method in methods
        if isinstance(method, dict) and isinstance(method.get("id"), str)
    }
    assert set(methods_by_id) == expected, payload

    terminal = terminal or set()
    assert terminal <= expected
    for method_id, method in methods_by_id.items():
        meta = method.get("_meta")
        terminal_meta = meta.get("terminal-auth") if isinstance(meta, dict) else None
        terminal_routed = method.get("type") == "terminal" or isinstance(
            terminal_meta, dict
        )
        assert terminal_routed == (method_id in terminal), method
        if terminal_routed:
            assert isinstance(terminal_meta, dict), method
            assert isinstance(terminal_meta.get("command"), str), method
            assert isinstance(terminal_meta.get("args"), list), method


def assert_runtime_auth_wrapper(
    image: str,
    *,
    runtime_command: str,
) -> None:
    """Prove the stable HyperCLI auth entrypoint resolves to this runtime."""
    payload = run_python(
        image,
        f"""
import json
import os
from pathlib import Path

generic = Path('/usr/local/bin/hypercli-runtime-auth')
specific = Path({runtime_command!r})
print(json.dumps({{
    'generic_is_link': generic.is_symlink(),
    'generic_target': os.path.realpath(generic),
    'specific_is_file': specific.is_file(),
    'specific_executable': os.access(specific, os.X_OK),
}}))
""",
    )
    assert payload == {
        "generic_is_link": True,
        "generic_target": runtime_command,
        "specific_is_file": True,
        "specific_executable": True,
    }, payload
    help_result = run(image, ["hypercli-runtime-auth", "--help"])
    assert f"Usage: {Path(runtime_command).name}" in help_result.stdout


def assert_models(
    image: str,
    *,
    agent_command: str,
    agent_args: str,
    env: dict[str, str] | None = None,
    mounts: list[tuple[Path, str]] | None = None,
) -> dict[str, Any]:
    payload = run_json(
        image,
        acp_command(
            "models",
            agent_command=agent_command,
            agent_args=agent_args,
        ),
        env=env,
        mounts=mounts,
    )
    assert isinstance(payload.get("agent"), dict), payload
    return payload


COMMON_PROBE = r"""
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path

workspace = Path("/home/node")
directories = [
    workspace / "GUIDES",
    workspace / "RESEARCH",
    workspace / "PLANS",
    workspace / "WORK_LOGS",
    workspace / "OUTBOX",
    workspace / "REPOS",
    workspace / ".scratch",
    workspace / ".agents",
    workspace / ".agents/skills",
    Path("/home/node/.coding-agent"),
]

hypercli_skills = sorted(
    path.parent.name
    for path in Path("/opt/hypercli/skills").glob("*/SKILL.md")
)
skills_index = Path("/home/node/SKILLS.md").read_text(encoding="utf-8")
agents_path = workspace / "AGENTS.md"
buzz_skill = workspace / ".agents/skills/buzz-cli/SKILL.md"
harness_skills = ["buzz-cli", *hypercli_skills] if buzz_skill.exists() else hypercli_skills

payload = {
    "uid": os.getuid(),
    "cwd": str(Path.cwd()),
    "sudo_user": subprocess.check_output(
        ["sudo", "-n", "whoami"],
        text=True,
    ).strip(),
    "runtime": Path("/opt/hypercli-coding/runtime").read_text().strip(),
    "agents_exists": agents_path.exists() or agents_path.is_symlink(),
    "agents_heading": agents_path.read_text(encoding="utf-8").splitlines()[0]
    if agents_path.exists()
    else None,
    "buzz_skill_has_name": buzz_skill.exists()
    and "name: buzz-cli" in buzz_skill.read_text(encoding="utf-8"),
    "hypercli_skill_names": {
        skill: f"name: {skill}" in (
            workspace / f".agents/skills/{skill}/SKILL.md"
        ).read_text(encoding="utf-8")
        for skill in hypercli_skills
    },
    "skills_index_mentions": {
        skill: f"`{skill}`" in skills_index
        for skill in hypercli_skills
    },
    "skills_index_target": os.readlink("/home/node/SKILLS.md"),
    "canonical_skill_links": {
        skill: os.readlink(workspace / f".agents/skills/{skill}")
        for skill in hypercli_skills
    },
    "directory_modes": {
        str(path): stat.S_IMODE(path.stat().st_mode)
        for path in directories
    },
    "tools": {
        tool: shutil.which(tool)
        for tool in (
            [
            "node",
            "npm",
            "python3",
            "hyper",
            "git",
            "jq",
            "rg",
            "ssh",
            "sudo",
            "tini",
            "acp",
            "Xvfb",
            "x11vnc",
            "websockify",
            "dbus-launch",
            "xfwm4",
            "xfce4-panel",
            "xfce4-terminal",
            "thunar",
            ]
            + (["buzz-agent", "buzz-dev-mcp"] if runtime == "buzz-agent" else [])
        )
    },
    "vanilla_buzz_cli": shutil.which("buzz"),
    "hidden_sprig": Path("/usr/local/lib/acp/buzz/sprig").is_file(),
    "workspaces_is_dir": Path("/home/node/shared").is_dir(),
    "legacy_buzz_nest_exists": (workspace / ".buzz").exists(),
    "base_prompt_in_image": Path(
        "/opt/hypercli-coding/nest/base_prompt.md"
    ).exists(),
    "base_prompt_in_workspace": (workspace / "base_prompt.md").exists(),
    "skill_links": {
        str(path): os.readlink(path)
        for path in [
            workspace / f"{harness}/skills/{skill}"
            for harness in [".claude", ".codex", ".goose"]
            for skill in harness_skills
        ]
    },
}
print(json.dumps(payload))
"""


def assert_common_contract(
    image: str,
    *,
    runtime: str,
    agent_command: str,
    agent_args: str,
    mcp_command: str,
    entrypoint: str,
) -> None:
    config = image_config(image)
    labels = config.get("Labels") or {}
    env = dict(
        item.split("=", 1)
        for item in config.get("Env") or []
        if "=" in item
    )

    assert config.get("Entrypoint") == [
        "/usr/bin/tini",
        "--",
        entrypoint,
    ], config.get("Entrypoint")
    assert config.get("WorkingDir") == "/home/node"
    assert config.get("Cmd") == ["sleep", "infinity"]
    if runtime == "buzz-agent":
        assert labels.get("org.hypercli.buzz_runtime") == "true"
    else:
        assert "org.hypercli.buzz_runtime" not in labels
    assert labels.get("org.hypercli.coding_workspace") == str(WORKSPACE)
    assert labels.get("org.hypercli.coding_runtime") == runtime
    assert env.get("CODING_AGENT_WORKSPACE_DIR") == str(WORKSPACE)
    assert env.get("CODING_AGENT_STATE_DIR") == str(STATE_DIR)
    assert env.get("HYPER_WORKSPACES_DIR") == str(WORKSPACES)
    assert env.get("HOME") == "/home/node"
    if runtime == "buzz-agent":
        assert env.get("BUZZ_ACP_AGENT_COMMAND") == agent_command
        assert env.get("BUZZ_ACP_AGENT_ARGS", "") == agent_args
        assert env.get("BUZZ_ACP_MCP_COMMAND", "") == mcp_command
        assert "BUZZ_ACP_BASE_PROMPT_FILE" not in env
    else:
        assert env.get("HYPER_ACP_AGENT_COMMAND") == agent_command
        assert env.get("HYPER_ACP_AGENT_ARGS", "") == agent_args
        assert "HYPER_ACP_BASE_PROMPT_FILE" not in env
        assert "BUZZ_ACP_AGENT_COMMAND" not in env
        assert "BUZZ_ACP_AGENT_ARGS" not in env
        assert "BUZZ_ACP_MCP_COMMAND" not in env
        assert "BUZZ_ACP_BASE_PROMPT_FILE" not in env

    assert_entrypoint_exit_passthrough(image)
    run(image, ["true"], env={"HYPER_DESKTOP_ENABLED": "1"})
    payload = run_python(image, COMMON_PROBE)
    assert payload["uid"] == 1000
    assert payload["cwd"] == str(WORKSPACE)
    assert payload["sudo_user"] == "root"
    assert payload["runtime"] == runtime
    assert payload["agents_exists"] is False
    assert payload["agents_heading"] is None
    assert payload["buzz_skill_has_name"] is (runtime == "buzz-agent")
    assert all(payload["hypercli_skill_names"].values())
    assert all(payload["skills_index_mentions"].values())
    assert payload["skills_index_target"] == "/opt/hypercli-coding/SKILLS.md"
    assert payload["canonical_skill_links"] == {
        skill: f"/opt/hypercli/skills/{skill}"
        for skill in payload["hypercli_skill_names"]
    }
    assert set(payload["directory_modes"].values()) == {0o700}
    assert all(payload["tools"].values()), payload["tools"]
    assert payload["vanilla_buzz_cli"] is None
    assert payload["hidden_sprig"] is True
    assert payload["workspaces_is_dir"] is True
    assert payload["legacy_buzz_nest_exists"] is False
    assert payload["base_prompt_in_image"] is False
    assert payload["base_prompt_in_workspace"] is False
    expected_skill_links = {
        f"../../.agents/skills/{skill}"
        for skill in payload["hypercli_skill_names"]
    }
    if runtime == "buzz-agent":
        expected_skill_links.add("../../.agents/skills/buzz-cli")
    assert set(payload["skill_links"].values()) == expected_skill_links
    expected_skill_count = len(payload["hypercli_skill_names"])
    if runtime == "buzz-agent":
        expected_skill_count += 1
    assert len(payload["skill_links"]) == 3 * expected_skill_count
    assert_workspace_persistence(image)


def assert_workspace_persistence(image: str) -> None:
    with tempfile.TemporaryDirectory() as persisted_name:
        persisted = Path(persisted_name)
        persisted.chmod(0o777)
        run(image, ["true"], mounts=[(persisted, "/home/node")])

        agents = persisted / "AGENTS.md"
        hypercli_skill = persisted / ".agents/skills/hypercli"
        skills_index = persisted / "SKILLS.md"
        buzz_skill = persisted / ".agents/skills/buzz-cli/SKILL.md"
        harness_skill_links = []
        if buzz_skill.exists():
            harness_skill_links = [
                persisted / f"{harness}/skills/buzz-cli"
                for harness in [".claude", ".codex", ".goose"]
            ]
        agents.write_text("user-managed AGENTS\n", encoding="utf-8")
        if buzz_skill.exists():
            buzz_skill.write_text("user-managed skill\n", encoding="utf-8")
        hypercli_skill.unlink()
        hypercli_skill.write_text(
            "user-managed HyperCLI skill\n",
            encoding="utf-8",
        )
        skills_index.unlink()
        skills_index.write_text(
            "user-managed skill index\n",
            encoding="utf-8",
        )
        for harness_skill_link in harness_skill_links:
            harness_skill_link.unlink()
            harness_skill_link.write_text(
                "user-managed harness skill replacement\n",
                encoding="utf-8",
            )

        claude = persisted / "CLAUDE.md"
        claude.write_text(
            "user-managed Claude instructions\n",
            encoding="utf-8",
        )

        run(image, ["true"], mounts=[(persisted, "/home/node")])
        agents_content = agents.read_text(encoding="utf-8")
        assert agents_content == "user-managed AGENTS\n"
        if buzz_skill.exists():
            assert buzz_skill.read_text(encoding="utf-8") == "user-managed skill\n"
        assert (
            hypercli_skill.read_text(encoding="utf-8")
            == "user-managed HyperCLI skill\n"
        )
        assert skills_index.read_text(encoding="utf-8") == (
            "user-managed skill index\n"
        )
        for harness_skill_link in harness_skill_links:
            assert not harness_skill_link.is_symlink()
            assert harness_skill_link.read_text(encoding="utf-8") == (
                "user-managed harness skill replacement\n"
            )
        assert not claude.is_symlink()
        assert (
            claude.read_text(encoding="utf-8")
            == "user-managed Claude instructions\n"
        )

def assert_user_config_preserved(
    image: str,
    *,
    relative_path: str,
    generated_contains: str,
    user_content: str,
    env: dict[str, str] | None = None,
) -> None:
    with tempfile.TemporaryDirectory() as home_name:
        home = Path(home_name)
        home.chmod(0o777)
        mounts = [(home, "/home/node")]

        run(image, ["true"], env=env, mounts=mounts)
        config = home / relative_path
        assert generated_contains in config.read_text(encoding="utf-8")

        config.unlink()
        run(image, ["true"], env=env, mounts=mounts)
        assert generated_contains in config.read_text(encoding="utf-8")

        config.write_text(user_content, encoding="utf-8")
        run(image, ["true"], env=env, mounts=mounts)
        assert config.read_text(encoding="utf-8") == user_content
