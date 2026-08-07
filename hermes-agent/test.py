#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread


IMAGE = sys.argv[1] if len(sys.argv) > 1 else "hypercli-hermes-agent:local"
API_KEY = "hermes-image-test-api-key-32-chars"
MODEL_KEY = "hermes-image-test-model-key"
PROMPT = "Hermes image contract ping"
REPLY = "Hermes image contract pong"
TEST_RUN_LABEL = "io.hypercli.hermes-test-run"
TEST_RUN_ID = os.environ.get("HERMES_TEST_RUN_ID", f"local-{uuid.uuid4().hex}")
EXPECTED_RUNTIME_TOOLS = (
    "cc",
    "curl",
    "ffmpeg",
    "git",
    "jq",
    "lsof",
    "make",
    "nano",
    "node",
    "npm",
    "npx",
    "pdftotext",
    "pip3",
    "pnpm",
    "python3",
    "rg",
    "sudo",
    "unzip",
    "vim",
    "xxd",
    "yarn",
    "zip",
    "corepack",
)


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=check, text=True, capture_output=True)


class ModelHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args: object) -> None:
        return

    def do_POST(self) -> None:
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        if self.headers.get("Authorization") != f"Bearer {MODEL_KEY}":
            self.send_error(401)
            return
        if not any(PROMPT in str(item.get("content")) for item in payload.get("messages", [])):
            self.send_error(400)
            return
        if payload.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            chunks = [
                {"id": "chatcmpl-hermes-image-test", "object": "chat.completion.chunk", "created": 1, "model": "mock-hermes", "choices": [{"index": 0, "delta": {"role": "assistant", "content": REPLY}, "finish_reason": None}]},
                {"id": "chatcmpl-hermes-image-test", "object": "chat.completion.chunk", "created": 1, "model": "mock-hermes", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
            ]
            for chunk in chunks:
                self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return
        body = json.dumps({
            "id": "chatcmpl-hermes-image-test",
            "object": "chat.completion",
            "created": 1,
            "model": "mock-hermes",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": REPLY}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 4, "completion_tokens": 4, "total_tokens": 8},
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def request_json(url: str, *, bearer: str | None = None, payload: dict | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if bearer:
        headers["Authorization"] = f"Bearer {bearer}"
    data = json.dumps(payload).encode() if payload is not None else None
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers, data=data), timeout=10) as response:
        return json.load(response)


def main() -> None:
    inspect = json.loads(run("docker", "image", "inspect", IMAGE).stdout)[0]["Config"]
    assert inspect["Entrypoint"] == ["/opt/hypercli-hermes/entrypoint.sh"]
    assert inspect["Cmd"] == ["gateway", "run"]
    assert "8642/tcp" in inspect["ExposedPorts"]
    assert inspect["Healthcheck"]["Test"][0] == "CMD-SHELL"

    sudo = run(
        "docker", "run", "--rm", "--user", "hermes", "--entrypoint", "/bin/sh", IMAGE,
        "-c", 'test "$(id -u)" -ne 0 && sudo -n id -u',
    )
    assert sudo.stdout.strip() == "0"

    runtime_tools = run(
        "docker", "run", "--rm", "--user", "hermes", "--entrypoint", "/bin/sh", IMAGE,
        "-c", 'for tool in "$@"; do command -v "$tool" >/dev/null || exit 1; done',
        "hermes-runtime-tools",
        *EXPECTED_RUNTIME_TOOLS,
    )
    assert runtime_tools.returncode == 0

    package_managers = run(
        "docker", "run", "--rm", "--user", "hermes", "--entrypoint", "/bin/sh", IMAGE,
        "-c", "corepack --version && pnpm --version && yarn --version",
    )
    assert package_managers.stdout.splitlines() == ["0.35.0", "11.2.2", "1.22.22"]

    version = run("docker", "run", "--rm", IMAGE, "--version")
    assert "Hermes Agent v" in version.stdout

    server = ThreadingHTTPServer(("0.0.0.0", 0), ModelHandler)
    Thread(target=server.serve_forever, daemon=True).start()
    model_port = server.server_address[1]
    container = f"hermes-image-test-{uuid.uuid4().hex[:10]}"
    volume = f"hermes-image-test-{uuid.uuid4().hex[:10]}"
    try:
        run(
            "docker", "volume", "create",
            "--label", f"{TEST_RUN_LABEL}={TEST_RUN_ID}",
            volume,
        )
        run(
            "docker", "run", "-d", "--name", container,
            "--label", f"{TEST_RUN_LABEL}={TEST_RUN_ID}",
            "--add-host", "host.docker.internal:host-gateway",
            "-p", "127.0.0.1::8642",
            "-v", f"{volume}:/opt/data",
            "-e", f"API_SERVER_KEY={API_KEY}",
            "-e", f"HYPER_API_KEY={MODEL_KEY}",
            "-e", f"HYPER_AGENTS_API_BASE=http://host.docker.internal:{model_port}",
            "-e", "HERMES_MODEL_TRANSPORT=chat_completions",
            "-e", "HERMES_DEFAULT_MODEL=mock-hermes",
            IMAGE,
        )
        port = run("docker", "port", container, "8642/tcp").stdout.strip().rsplit(":", 1)[1]
        base = f"http://127.0.0.1:{port}"
        for _ in range(60):
            try:
                if request_json(f"{base}/health").get("status") == "ok":
                    break
            except Exception:
                time.sleep(1)
        else:
            raise AssertionError(run("docker", "logs", container, check=False).stdout)

        result = request_json(
            f"{base}/v1/chat/completions",
            bearer=API_KEY,
            payload={"model": "hermes-agent", "messages": [{"role": "user", "content": PROMPT}], "stream": False},
        )
        assert result["choices"][0]["message"]["content"] == REPLY

        seeded = run(
            "docker", "run", "--rm", "-v", f"{volume}:/opt/data", IMAGE,
            "python", "-c",
            "from pathlib import Path; print(Path('/opt/data/config.yaml').read_text())",
        ).stdout
        assert "key_env: HYPER_AGENTS_API_KEY" in seeded
        assert "api: ${env:HERMES_INFERENCE_API_BASE}" in seeded
        assert "default: ${env:HERMES_DEFAULT_MODEL}" in seeded
        assert "_config_version: 33" in seeded
        assert MODEL_KEY not in seeded

        dev_model_base = run(
            "docker", "run", "--rm",
            "-e", "HYPER_AGENTS_API_BASE=https://api.dev.hypercli.com/agents",
            IMAGE,
            "sh", "-c", "printf '%s' \"${HERMES_INFERENCE_API_BASE}\"",
        ).stdout
        assert dev_model_base.rstrip().endswith("https://api.agents.dev.hypercli.com/v1")

        custom_model_base = run(
            "docker", "run", "--rm",
            "-e", "HYPER_AGENTS_API_BASE=http://models.internal/",
            IMAGE,
            "sh", "-c", "printf '%s' \"${HERMES_INFERENCE_API_BASE}\"",
        ).stdout
        assert custom_model_base.rstrip().endswith("http://models.internal/v1")

        overridden_model_base = run(
            "docker", "run", "--rm",
            "-e", "HYPER_AGENTS_API_BASE=https://api.dev.hypercli.com/agents",
            "-e", "HERMES_INFERENCE_API_BASE=https://override.example/v1",
            IMAGE,
            "sh", "-c", "printf '%s' \"${HERMES_INFERENCE_API_BASE}\"",
        ).stdout
        assert overridden_model_base.rstrip().endswith("https://override.example/v1")

        run(
            "docker", "run", "--rm", "--entrypoint", "/bin/sh",
            "-v", f"{volume}:/opt/data", IMAGE,
            "-c", "chown -R 12345:12346 /opt/data && rm -rf /opt/data/skills/hypercli",
        )
        ownership = run(
            "docker", "run", "--rm", "-e", "PUID=12345", "-e", "PGID=12346",
            "-v", f"{volume}:/opt/data", IMAGE,
            "stat", "-c", "%u:%g", "/opt/data/skills/hypercli",
        ).stdout
        assert ownership.rstrip().endswith("12345:12346")

        marker = "# preserve-existing-config"
        run(
            "docker", "run", "--rm", "-v", f"{volume}:/opt/data", IMAGE,
            "python", "-c",
            f"from pathlib import Path; p=Path('/opt/data/config.yaml'); p.write_text(p.read_text() + {marker!r} + '\\n')",
        )
        preserved = run(
            "docker", "run", "--rm", "-v", f"{volume}:/opt/data", IMAGE,
            "python", "-c",
            "from pathlib import Path; print(Path('/opt/data/config.yaml').read_text())",
        ).stdout
        assert marker in preserved
    finally:
        server.shutdown()
        run("docker", "rm", "-f", container, check=False)
        run("docker", "volume", "rm", "-f", volume, check=False)

    print("Hermes agent image contract passed")


if __name__ == "__main__":
    main()
