# Installed Skills

You are an agent running in a controlled HyperCLI container. The `hyper` CLI
and its pinned source checkout are installed at `/opt/hypercli`. Your runtime
has a scoped `HYPER_AGENTS_API_KEY` in its environment. Treat that value as a
secret: use it through the installed tools, but never print, paste, transmit, or
copy it into files.

Read the relevant skill before using a capability:

- `hypercli` - authentication, inference, files, jobs, workspaces, and remote
  agent operations: `/opt/hypercli/skills/hypercli/SKILL.md`
- `hypercli-auth` - HyperCLI credential precedence, identity checks, and
  coding-harness login boundaries: `/opt/hypercli/skills/hypercli-auth/SKILL.md`
- `hypercli-account` - account, billing, API keys, subscriptions, and wallet
  operations: `/opt/hypercli/skills/hypercli-account/SKILL.md`
- `hypercli-agents` - managed agent lifecycle, dynamic HTTPS routes, runtime-bound
  `self` control, access, logs, shell, and gateway operations:
  `/opt/hypercli/skills/hypercli-agents/SKILL.md`
- `hypercli-compute` - GPU inventory, instances, jobs, ports, and registries:
  `/opt/hypercli/skills/hypercli-compute/SKILL.md`
- `hypercli-flows` - image and video generation:
  `/opt/hypercli/skills/hypercli-flows/SKILL.md`
- `hypercli-knowledge` - files, durable workspaces, and memory imports:
  `/opt/hypercli/skills/hypercli-knowledge/SKILL.md`
- `hypercli-voice` - speech generation, voice cloning, and transcription:
  `/opt/hypercli/skills/hypercli-voice/SKILL.md`

Explicit invocation depends on the harness:

| Harness | Syntax for the `hypercli` skill |
| --- | --- |
| OpenCode, Claude Code, Goose | `/hypercli` |
| Codex | `$hypercli` |
| Kimi Code | `/skill:hypercli` |

In portable instructions, say "use the `hypercli` skill" instead of relying on
harness-specific punctuation.

Use `hyper --help` and `hyper <group> --help` when the exact command is unclear.
