# Buzz Runtime Contract

These images run Buzz's shipped ACP adapter remotely. The desktop remains the
source of agent identity, access policy, prompt composition, channel state, and
launch requests. Images must not invent a second prompt or reinterpret those
fields.

## Shared contract

- Home: `/home/node`
- Working directory: `/home/node/.buzz`
- Project instructions: `/home/node/.buzz/AGENTS.md`
- Shared skills: `/home/node/.buzz/.agents/skills`
- Adapter: `/usr/local/bin/buzz-acp`
- The image build compares `buzz/AGENTS.md` byte-for-byte with Buzz's
  `nest_agents.md`; update the pinned Buzz source and this copy together.
- `BUZZ_ACP_SYSTEM_PROMPT` contains only the desktop-composed agent prompt.
  `buzz-acp` selects the runtime-specific ACP transport and sends it exactly
  once.
- Hosted launches always set `BUZZ_ACP_DISPLAY_NAME`; compatible names also
  enable `BUZZ_ACP_TEXT_MENTIONS` so manually typed mentions work when the
  desktop cannot resolve a remote agent in its composer.
- Hosted launches set `BUZZ_ACP_REQUIRE_REPLY=true`. The shared `buzz-acp`
  guard applies Buzz's canonical bounded reminder to every external harness;
  images must not append runtime-specific reply policies to `AGENTS.md`.

## Runtime matrix

| Runtime | ACP child | MCP command | Prompt transport | Runtime state and skills |
| --- | --- | --- | --- | --- |
| OpenCode | `opencode acp` | none | ACP v2 `systemPrompt`; ACP v1 prompt framing | `.config/opencode`, `.local/share/opencode`, `.local/state/opencode`, `.cache/opencode`; `.buzz/.agents/skills` |
| Codex | `codex-acp` | `buzz-dev-mcp` | ACP v2 `systemPrompt`; ACP v1 prompt framing | `.codex`; `.buzz/.agents/skills` with `.codex/skills` compatibility |
| Claude Code | `claude-agent-acp` | none | `_meta.systemPrompt.append` | `.claude`, `.claude.json`; `.buzz/CLAUDE.md -> AGENTS.md`, `.buzz/.claude/skills` |
| Goose | `goose acp` | none | `_goose/unstable/session/system-prompt/set`, then ACP fallback | `.goose`; `.buzz/.agents/skills` |
| Kimi Code | `kimi acp` | none | ACP v2 `systemPrompt`; ACP v1 prompt framing | `.kimi-code`; `.buzz/.agents/skills` |

OpenClaw is a separate gateway runtime and is not part of this ACP matrix.

## Regression requirements

Image and provider tests must verify:

1. Every runtime uses the exact command, arguments, and MCP value above.
2. `AGENTS.md` matches the pinned Buzz source and is installed under `.buzz`.
3. The composed prompt canary reaches each runtime exactly once through its
   native transport.
4. Ordinary ACP assistant text remains activity output and is never published
   as a Buzz message by the transport.
5. A harness that has useful output follows the canonical prompt and publishes
   it with the Buzz CLI or runtime MCP path.
6. Display-name and text-mention variables cannot be overridden by user env.
7. The provider-owned reply guard cannot be overridden by user env, uses one
   hard deadline, and accepts silence after the canonical two reminders.
