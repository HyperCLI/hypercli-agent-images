from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any


NEST = Path("/home/node/.buzz")
WORKSPACES = Path("/home/node/shared")
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
    container_name = f"hypercli-buzz-entrypoint-exit-{uuid.uuid4().hex}"
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
        "buzz-acp",
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

nest = Path("/home/node/.buzz")
directories = [
    nest,
    nest / "GUIDES",
    nest / "RESEARCH",
    nest / "PLANS",
    nest / "WORK_LOGS",
    nest / "OUTBOX",
    nest / "REPOS",
    nest / ".scratch",
    nest / ".agents",
    nest / ".agents/skills",
    nest / ".agents/skills/buzz-cli",
]

hypercli_skills = sorted(
    path.parent.name
    for path in Path("/opt/hypercli/skills").glob("*/SKILL.md")
)
skills_index = Path("/home/node/SKILLS.md").read_text(encoding="utf-8")

payload = {
    "uid": os.getuid(),
    "cwd": str(Path.cwd()),
    "sudo_user": subprocess.check_output(
        ["sudo", "-n", "whoami"],
        text=True,
    ).strip(),
    "runtime": Path("/opt/hypercli-buzz/runtime").read_text().strip(),
    "agents_heading": (
        nest / "AGENTS.md"
    ).read_text(encoding="utf-8").splitlines()[0],
    "skill_has_name": "name: buzz-cli" in (
        nest / ".agents/skills/buzz-cli/SKILL.md"
    ).read_text(encoding="utf-8"),
    "hypercli_skill_names": {
        skill: f"name: {skill}" in (
            nest / f".agents/skills/{skill}/SKILL.md"
        ).read_text(encoding="utf-8")
        for skill in hypercli_skills
    },
    "skills_index_mentions": {
        skill: f"`{skill}`" in skills_index
        for skill in hypercli_skills
    },
    "skills_index_target": os.readlink("/home/node/SKILLS.md"),
    "canonical_skill_links": {
        skill: os.readlink(nest / f".agents/skills/{skill}")
        for skill in hypercli_skills
    },
    "directory_modes": {
        str(path): stat.S_IMODE(path.stat().st_mode)
        for path in directories
    },
    "tools": {
        tool: shutil.which(tool)
        for tool in [
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
            "buzz",
            "buzz-acp",
            "buzz-dev-mcp",
        ]
    },
    "workspaces_is_dir": Path("/home/node/shared").is_dir(),
    "nested_workspaces_exists": (nest / "workspaces").exists(),
    "base_prompt_in_image": Path(
        "/opt/hypercli-buzz/nest/base_prompt.md"
    ).exists(),
    "base_prompt_in_nest": (nest / "base_prompt.md").exists(),
    "skill_links": {
        str(path): os.readlink(path)
        for path in [
            nest / f"{harness}/skills/{skill}"
            for harness in [".claude", ".codex", ".goose"]
            for skill in ["buzz-cli", *hypercli_skills]
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
    claude_compatibility: bool = False,
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
    assert labels.get("org.hypercli.buzz_runtime") == "true"
    assert labels.get("org.hypercli.buzz_workspace") == str(NEST)
    assert labels.get("org.hypercli.coding_runtime") == runtime
    assert env.get("CODING_AGENT_WORKSPACE_DIR") == str(NEST)
    assert env.get("HYPER_WORKSPACES_DIR") == str(WORKSPACES)
    assert env.get("HOME") == "/home/node"
    assert env.get("BUZZ_ACP_AGENT_COMMAND") == agent_command
    assert env.get("BUZZ_ACP_AGENT_ARGS", "") == agent_args
    assert env.get("BUZZ_ACP_MCP_COMMAND", "") == mcp_command

    assert_entrypoint_exit_passthrough(image)
    payload = run_python(image, COMMON_PROBE)
    assert payload["uid"] == 1000
    assert payload["cwd"] == str(NEST)
    assert payload["sudo_user"] == "root"
    assert payload["runtime"] == runtime
    assert payload["agents_heading"] == "# Buzz Nest"
    assert payload["skill_has_name"] is True
    assert all(payload["hypercli_skill_names"].values())
    assert all(payload["skills_index_mentions"].values())
    assert payload["skills_index_target"] == "/opt/hypercli-buzz/SKILLS.md"
    assert payload["canonical_skill_links"] == {
        skill: f"/opt/hypercli/skills/{skill}"
        for skill in payload["hypercli_skill_names"]
    }
    assert set(payload["directory_modes"].values()) == {0o700}
    assert all(payload["tools"].values()), payload["tools"]
    assert payload["workspaces_is_dir"] is True
    assert payload["nested_workspaces_exists"] is False
    assert payload["base_prompt_in_image"] is False
    assert payload["base_prompt_in_nest"] is False
    assert set(payload["skill_links"].values()) == {
        "../../.agents/skills/buzz-cli",
        *{
            f"../../.agents/skills/{skill}"
            for skill in payload["hypercli_skill_names"]
        },
    }
    assert len(payload["skill_links"]) == 3 * (
        len(payload["hypercli_skill_names"]) + 1
    )
    assert_nest_persistence(
        image,
        claude_compatibility=claude_compatibility,
    )


def assert_nest_persistence(
    image: str,
    *,
    claude_compatibility: bool,
) -> None:
    with tempfile.TemporaryDirectory() as persisted_name:
        persisted = Path(persisted_name)
        persisted.chmod(0o777)
        run(image, ["true"], mounts=[(persisted, "/home/node")])

        agents = persisted / ".buzz/AGENTS.md"
        skill = persisted / ".buzz/.agents/skills/buzz-cli/SKILL.md"
        hypercli_skill = persisted / ".buzz/.agents/skills/hypercli"
        skills_index = persisted / "SKILLS.md"
        harness_skill_links = [
            persisted / f".buzz/{harness}/skills/buzz-cli"
            for harness in [".claude", ".codex", ".goose"]
        ]
        agents.write_text("user-managed AGENTS\n", encoding="utf-8")
        skill.write_text("user-managed skill\n", encoding="utf-8")
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

        claude = persisted / ".buzz/CLAUDE.md"
        if claude_compatibility:
            assert claude.is_symlink()
            assert os.readlink(claude) == "AGENTS.md"
            claude.unlink()
            claude.write_text(
                "user-managed Claude instructions\n",
                encoding="utf-8",
            )

        run(image, ["true"], mounts=[(persisted, "/home/node")])
        agents_content = agents.read_text(encoding="utf-8")
        assert agents_content == "user-managed AGENTS\n"
        assert skill.read_text(encoding="utf-8") == "user-managed skill\n"
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
        if claude_compatibility:
            assert not claude.is_symlink()
            assert (
                claude.read_text(encoding="utf-8")
                == "user-managed Claude instructions\n"
            )
        else:
            assert not claude.exists()

    with tempfile.TemporaryDirectory() as bad_name:
        bad_home = Path(bad_name)
        bad_home.chmod(0o777)
        workspaces = bad_home / "workspaces"
        workspaces.mkdir()
        (bad_home / ".buzz").symlink_to("workspaces")
        result = run(
            image,
            ["true"],
            mounts=[(bad_home, "/home/node")],
            check=False,
        )
        assert result.returncode != 0
        assert not any(workspaces.iterdir())


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
