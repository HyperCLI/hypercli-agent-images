# HyperCLI Hosted Buzz Runtimes

This directory builds the coding-agent images used when Buzz Desktop selects a
`hypercli-*` backend. It documents the boundary between the unmodified Desktop
provider protocol, HyperCLI's provider adapter, the HyperCLI deployments API,
and the runtime-specific ACP child inside the container.

This is the canonical human architecture document for the hosted Buzz images.
`AGENTS.md` contains maintainer guardrails. `nest/AGENTS.md` and `SKILLS.md` are
runtime content copied into an agent container.

## System Boundary

```text
Buzz Desktop
  -> one-shot HyperCLI backend-provider process
  -> hypercli-sdk
  -> HyperCLI deployments API
  -> HyperClaw/Lagoon
  -> hypercli-buzz-<runtime> image
  -> buzz-acp
  -> runtime ACP child
  -> Buzz relay
```

Buzz Desktop owns:

- persona and agent identity;
- relay URL, private key, authorization tag, and owner identity;
- effective prompt, model, provider, timeouts, and access policy;
- channel membership and the selected backend provider;
- the portable resolved `launch` block.

The HyperCLI provider owns:

- provider-schema validation;
- portable-launch validation and environment precedence;
- runtime and canonical image selection;
- translation into the HyperCLI deployment request;
- stable identity lookup, idempotent create/start, and readiness polling.

HyperClaw and Lagoon own:

- runtime-key issuance and scopes;
- image scheduling, storage projection, and pod lifecycle;
- deployment state and authenticated lifecycle operations.

The image owns only process setup, installed runtime binaries, workspace
initialization, compatibility links, and the runtime-specific ACP command.

## Local And Hosted Installation

Buzz's Settings > Agents screen discovers and installs local harnesses. For
example, the Goose Install action runs Goose's local CLI installer through
Tauri. OpenCode can appear Ready because its binary is already available on
the Desktop machine.

Those actions do not install software in a hosted deployment. Hosted runtimes
are immutable images with the selected CLI and adapter already installed.
Desktop's local install and login machinery is therefore useful source
material, but it is not part of the remote provider protocol.

## Provider Protocol

Buzz starts a fresh provider process for every operation:

1. The process receives no normal command-line arguments.
2. Desktop writes one JSON object plus a newline to stdin and closes stdin.
3. The provider writes one JSON response to stdout.
4. Diagnostics go to stderr and must not contain secrets.

Protocol version 1 supports only:

- `info`, with a 10-second Desktop timeout;
- `deploy`, with a 600-second Desktop timeout.

There is no provider `start`, `stop`, `delete`, `update`, `exec`, `logs`,
`status`, `install`, or `login` operation. Do not infer those operations from
similarly named UI actions.

The resolved `agent.launch` block is authoritative when present:

- `launch.command` and `launch.args` identify the selected portable harness;
- `launch.policy_env` supplies descriptor policy defaults;
- `launch.env` supplies the fully resolved descriptor and user environment;
- `launch.owner_pubkey` supplies the resolved owner.

Environment precedence is `policy_env`, then `env`. Legacy top-level agent
fields are accepted only for saved clients without a resolved launch block.
The provider must reject invalid POSIX keys and remove provider-owned keys
before applying its canonical values.

The portable contract expects a command name. `launch.command` selects the
hosted runtime; legacy requests without `launch` fall back to
`agent.agent_command`. Runtime-named provider executables are discovery and
saved-provider compatibility aliases, not runtime selectors, because Desktop
stages the selected binary as `provider[.exe]`. The provider defensively
normalizes a `/`- or `\\`-qualified value and optional `.exe` to a known
basename, then chooses the canonical image and absolute child command while
preserving descriptor arguments. Missing or unknown commands are rejected;
display fields and saved provider config do not select a runtime.

## Why We Do Not Import The Kubernetes Provider

Upstream's `buzz-backend-kubernetes` is a direct Kubernetes reconciler. It owns
Kubernetes configuration, namespaces, pods, image policy, observation,
garbage collection, and reconciliation. HyperCLI deliberately delegates those
responsibilities to the deployments API and Lagoon, so importing or copying
the reconciler would create two orchestration layers and immediate drift.

The reusable upstream boundaries are:

- provider request, response, and portable launch wire types;
- environment validation, precedence, and provider-owned key rules;
- sanitized provider-wire golden fixtures;
- setup payload types parsed by `buzz-acp`;
- naming, error classification, and reconciliation invariants as references.

The preferred future extraction is small shared crates such as
`buzz-backend-wire` and `buzz-backend-env`, not a dependency on the whole
Kubernetes provider. Until those exist, upstream wire fixtures and source are
conformance references and our orchestration remains provider-specific.

## Deployment Contract

All hosted Buzz coding runtimes use:

| Property | Value |
| --- | --- |
| Size | largest currently available entitlement slot (`large` > `medium` > `small`) |
| Entrypoint command | `/usr/local/bin/buzz-acp` |
| Restart | `false` |
| Routes | none |
| Home and sync root | `/home/node` |
| Working directory | `/home/node/.buzz` |
| Sync owner | UID/GID `1000` |
| Runtime scopes | `agents:none`, `files:*`, `flows:*`, `models:*`, `voice:*`, `web:*`, `workspaces:*` |

The stable handle is derived from the Nostr public key. Provider `deploy` is
idempotent:

- a matching running deployment is reused;
- a booting deployment is polled;
- a stopped deployment is started in place with the current translated launch
  request;
- a create conflict is recovered by looking up the same stable deployment.
- a create-time slot race refreshes capacity and may fall back to an
  unattempted lower available tier.

Readiness succeeds only at `RUNNING`. `PENDING`, `RESTORING`, `SYNCING`, and
`STARTING` are polled. Terminal failure states and the readiness timeout return
a sanitized error without upstream response bodies or secrets.

## Runtime Matrix

| Hosted runtime | Canonical image | Portable command | Injected ACP child | Child args | MCP command | Prompt transport | Runtime state |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Buzz Agent | `ghcr.io/hypercli/hypercli-buzz-agent:latest` | `buzz-agent` | `/usr/local/bin/buzz-agent` | none | `/usr/local/bin/buzz-dev-mcp` | ACP v2 `systemPrompt`; ACP v1 prompt framing | environment-only for hosted Anthropic auth |
| OpenCode | `ghcr.io/hypercli/hypercli-buzz-opencode:latest` | `opencode` | `/usr/local/bin/opencode` | `acp` | none | ACP v2 `systemPrompt`; ACP v1 prompt framing | `.config/opencode`, `.local/share/opencode`, `.local/state/opencode`, `.cache/opencode` |
| Codex | `ghcr.io/hypercli/hypercli-buzz-codex:latest` | `codex-acp` | `/usr/local/bin/codex-acp` | none | `/usr/local/bin/buzz-dev-mcp` | ACP v2 `systemPrompt`; ACP v1 prompt framing | `.codex` |
| Claude Code | `ghcr.io/hypercli/hypercli-buzz-claude:latest` | `claude-agent-acp` | `/usr/local/bin/claude-agent-acp` | none | none | `_meta.systemPrompt.append` | `.claude`, `.claude.json` |
| Goose | `ghcr.io/hypercli/hypercli-buzz-goose:latest` | `goose` | `/usr/local/bin/goose` | `acp` | none | `_goose/unstable/session/system-prompt/set`, then ACP fallback | `.goose` |
| Kimi Code | `ghcr.io/hypercli/hypercli-buzz-kimi-code:latest` | `kimi` | `/usr/local/bin/kimi` | `acp` | none | ACP v2 `systemPrompt`; ACP v1 prompt framing | `.kimi-code` |

OpenClaw is a separate gateway runtime. `buzz-agent` is upstream Buzz's native
ACP runtime. The upstream Sprig multicall binary still supplies `buzz`,
`buzz-agent`, and `buzz-dev-mcp`; the stable `buzz-acp` executable is built
from HyperCLI's `hypercli-buzz-acp` package and is not a Sprig symlink.

## Container Injection

### Files and directories

The image must provide:

- `/usr/local/bin/buzz-acp`, built from the exact pinned HyperCLI commit;
- the runtime CLI and any required ACP adapter from the matrix above;
- `/opt/hypercli` at a pinned HyperCLI commit;
- `/opt/hypercli-buzz/nest/AGENTS.md`, copied from `nest/AGENTS.md`;
- `/opt/hypercli-buzz/nest/.agents/skills/buzz-cli/SKILL.md`, copied from
  pinned Buzz `nest_skill.md`;
- `/opt/hypercli-buzz/SKILLS.md`, the installed-skill index;
- `/home/node/workspaces` and `/home/node/.buzz`, owned by UID/GID 1000.

Initialization creates the standard Buzz nest directories and copies template
files only when the destination does not exist. It must not overwrite a
user-managed file, directory, or symlink.

Every runtime entrypoint performs its compatibility setup and then `exec`s the
shared entrypoint, which in turn `exec`s the provider-supplied command through
`tini`. Hosted launches supply `/usr/local/bin/buzz-acp`; that command replaces
the image's fallback `sleep infinity`, and its exit status becomes the
container exit status.

`nest/AGENTS.md` must remain byte-for-byte equal to the pinned Buzz Desktop
`desktop/src-tauri/src/managed_agents/nest_agents.md`. It is installed as
`/home/node/.buzz/AGENTS.md`. Maintainer guidance belongs in this directory's
top-level `AGENTS.md`, not in the runtime prompt.

HyperCLI skills are linked into `.buzz/.agents/skills`. Compatibility links
also expose them through:

- `.buzz/.claude/skills`;
- `.buzz/.codex/skills`;
- `.buzz/.goose/skills`.

Claude additionally receives `.buzz/CLAUDE.md -> AGENTS.md`. Existing
user-managed paths always win. Its entrypoint also creates a non-secret
`.claude/settings.json` model catalog only when absent.

### Runtime inference environment

Lagoon injects `HYPER_AGENTS_API_KEY` and `HYPER_API_BASE` into the container.
The image entrypoints do not translate or persist that credential.
`hypercli-buzz-acp` performs runtime-specific translation immediately before
every lazy child spawn and respawn:

- Claude Code: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`;
- Codex: a non-secret `CODEX_CONFIG` custom-provider overlay whose `env_key`
  points at `HYPER_AGENTS_API_KEY` and whose wire API is `responses`;
- Kimi Code 0.31: the native in-memory `KIMI_MODEL_*` overlay.

The mapping is all-or-nothing and does not overwrite an explicit native
runtime environment, preventing a HyperCLI key/vendor URL mix. Set
`HYPERCLI_RUNTIME_INFERENCE=native` when a synced vendor login/config should be
used instead. Codex configuration is reproducible, but inference remains
blocked until the HyperCLI gateway exposes an OpenAI Responses surface.

### Runtime-native authentication

Claude Code, Codex, and Kimi Code images expose a stable
`/usr/local/bin/hypercli-runtime-auth` command for authenticated remote exec or
PTY sessions. It resolves to the runtime-specific wrapper installed in the
same image:

- Claude Code: `hypercli-claude-auth status|login|setup-token|logout`;
- Codex: `hypercli-codex-auth status|login|logout`;
- Kimi Code: `hypercli-kimi-auth status|login`.

Login runs inside the hosted runtime so native credentials persist beneath the
sync-backed home directory. These commands are an image/exec contract; the
one-shot deployment provider does not proxy interactive authentication and
credentials must not be copied into its launch request.

Every wrapper's `status` action prints exactly one JSON object with `runtime`
and `authenticated` (`true`, `false`, or `null` when the upstream CLI exposes
no status probe) and exits successfully. Exit code 2 is reserved for invalid
wrapper usage.

### Provider-owned environment

The provider must inject and protect these categories:

| Category | Keys |
| --- | --- |
| Identity | `BUZZ_PRIVATE_KEY`, `NOSTR_PRIVATE_KEY` |
| Relay | `BUZZ_RELAY_URL`, optional `BUZZ_AUTH_TAG` |
| ACP child | `BUZZ_ACP_AGENT_COMMAND`, `BUZZ_ACP_AGENT_ARGS`, `BUZZ_ACP_MCP_COMMAND` |
| Owner and access | `BUZZ_ACP_AGENT_OWNER`, `BUZZ_ACP_RESPOND_TO`, `BUZZ_ACP_RESPOND_TO_ALLOWLIST` |
| Display and mentions | `BUZZ_ACP_DISPLAY_NAME`, `BUZZ_ACP_TEXT_MENTIONS` for compatible names |
| Reply behavior | `BUZZ_ACP_REQUIRE_REPLY=true` |
| Prompt and model | `BUZZ_ACP_SYSTEM_PROMPT`, `BUZZ_ACP_MODEL`, `BUZZ_ACP_SESSION_TITLE` |
| Pooling | `BUZZ_ACP_AGENTS`, `BUZZ_ACP_LAZY_POOL`, `BUZZ_ACP_RELAY_OBSERVER` |
| Event handling | `BUZZ_ACP_MULTIPLE_EVENT_HANDLING=steer`, `BUZZ_ACP_DEDUP=queue` |
| Workspaces | `HYPER_WORKSPACES_BOOT_SYNC=1`, `HYPER_WORKSPACES_DIR=/home/node/workspaces`, `HYPER_WORKSPACES_SYNC_READY_ONLY=1`, optional selected workspace |

The provider also projects validated non-reserved `launch.env` values. It must
not allow user environment to override identity, relay, authorization,
runtime command, text mentions, reply guard, or workspace bootstrap fields.

`BUZZ_ACP_SYSTEM_PROMPT` contains only Desktop's composed prompt. `buzz-acp`
selects the runtime-specific transport and sends the prompt exactly once. An
image must not append its own response policy or duplicate the prompt in a
runtime-specific instruction file.

## Messages, Mentions, And Replies

ACP activity and thinking output are observer telemetry. Desktop does not
publish an ACP `agent_message_chunk` as the agent's final Buzz message. The
runtime must publish with `buzz messages send`, `buzz reactions add`, or the
equivalent registered MCP command.

Hosted images enable Buzz's shared reply guard. If a genuine ACP `end_turn`
occurs without an attempted publish, `buzz-acp` sends the canonical reminder
in the same session. The guard is adapter-neutral, shares the original hard
deadline, retries at most twice, and then accepts silence. Do not replace it
with runtime-specific prompt text or automatic publication of streamed output.

`respond_to` authorizes who may instruct the agent. Text mention fallback is a
separate routing compatibility feature. The provider always supplies the
display name and enables text mentions only for a valid compatible name.
Matching is boundary-safe and case-insensitive. It does not bypass
`owner-only`, `allowlist`, `anyone`, or `nobody` authorization.

## Desktop Lifecycle Semantics

Desktop projects provider status from its stored `backend_agent_id`, not from
the live HyperCLI deployment. Presence is a separate relay signal.

| Desktop action | Provider call | Hosted effect |
| --- | --- | --- |
| Create with provider | `info`, then `deploy` | Creates or reuses the stable deployment and stores its ID. |
| Play/deploy an undeployed record | `info`, then `deploy` | Rebuilds the current portable request. |
| Add or mention an undeployed agent | conditional `deploy` | Deploys after membership when no provider ID exists. |
| Add or mention a deployed agent | none | Changes membership only. |
| Save settings | none | Persists Desktop state; does not hot-reload the pod. |
| Remove from channel | none | Changes membership only; the pod keeps running. |
| Stop current turn | none | Sends observer `cancel_turn`; does not stop the deployment. |
| Shutdown/Stop running agents | none | Sends signed `!shutdown` through a resolvable channel. |
| Delete agent | none | Best-effort shutdown, then local/relay deletion; an unreachable deployment can be orphaned. |
| Desktop launch or quit | none | Provider-backed agents are excluded from local process restore/shutdown. |

Normal UI can suppress Play while a stale provider ID still says `deployed`,
even after the remote deployment has stopped. Provider idempotency makes a
future explicit `deploy` safe but cannot repair Desktop's local status without
a new Desktop lifecycle operation.

Hosted `buzz-acp` exits after an authorized exact `!shutdown`. With
`restart: false`, that process exit must terminate the pod. HyperCLI lifecycle
operations remain available through the authenticated agents API and CLI; they
are not provider protocol operations.

## Authentication Boundary

Desktop's provider deploy response contains only `agent_id`. Settings > Agents
login commands execute local adapters and terminals. They cannot execute in a
provider-hosted pod or return a remote verification URL/code through provider
protocol v1.

Hosted HyperCLI inference does not require vendor login for Claude or Kimi;
the ACP child receives Lagoon's short-lived credential. Vendor login remains
useful for native models/features and is selected explicitly with
`HYPERCLI_RUNTIME_INFERENCE=native`. Codex device login and analogous
Claude/OpenCode flows still require a live remote PTY, structured URL/code
extraction, status, input, cancellation, and resume. Do not encode a challenge
in `agent_id` or a provider error.

ACP authentication is useful as a protocol reference but does not install a
runtime. Terminal authentication tells the client to launch a separate
interactive process; it does not transport that terminal through the current
Desktop provider interface.

## Persistence

The current hosted contract enables sync at `/home/node`. This preserves more
state than the minimum needed by task-oriented coding agents. Narrowing future
sync to canonical runtime state such as `.claude`, `.codex`, `.goose`, or other
explicit authentication/configuration directories is a separate storage
change. Do not describe that proposal as shipped behavior.

Workspace initialization and HyperCLI workspace sync are distinct. The Buzz
nest lives at `/home/node/.buzz`; synced HyperCLI workspaces live under
`/home/node/workspaces`.

## Regression Gates

Provider, SDK, ACP, or image changes must verify:

1. Sanitized provider fixtures deserialize and round-trip the exact wire keys.
2. Every supported `launch.command` basename selects the expected runtime,
   canonical image, absolute child, args, and MCP command; the generic
   executable and compatibility aliases expose the same provider protocol.
3. Missing and unknown launch commands are rejected; path-qualified known
   commands and optional case-insensitive `.exe` normalize to the same
   canonical runtime, and the caller-supplied path is never executed.
4. Environment precedence matches upstream and provider-owned keys cannot be
   overridden.
5. Every image contains the exact child command, args, MCP command, runtime
   state paths, and skill links in the matrix.
6. `nest/AGENTS.md` matches pinned Buzz and survives repeated initialization.
7. The real `tini` and setup entrypoint chain terminates promptly and preserves
   the launched command's nonzero exit status.
8. A real Nostr keypair and owner-signed, agent-mentioned `!shutdown` drives
   online-to-offline presence, relay close, and candidate-container exit.
9. The composed prompt reaches each runtime exactly once.
10. ACP assistant text remains activity until the runtime explicitly publishes.
11. Reply-guard retries are bounded under one hard deadline.
12. Text mentions and author authorization remain independent.
13. Provider deploy reuses running state and restarts stopped state in place.
14. Tests do not claim Desktop settings, membership, shutdown, deletion, or
    restoration invokes a provider lifecycle operation.

Image candidates should be tested by immutable SHA tag. Promotion to `latest`
must follow the runtime contract and offline ACP gates, including real Buzz
Agent, OpenCode, and Goose inference behavior where supported.

## Source Map

Pinned upstream Buzz dependencies:

- provider request construction: `desktop/src-tauri/src/commands/agents_deploy.rs`;
- provider invocation: `desktop/src-tauri/src/managed_agents/backend.rs`;
- local discovery/install: `desktop/src-tauri/src/managed_agents/discovery.rs`
  and `desktop/src-tauri/src/commands/agent_discovery.rs`;
- remote status projection: `desktop/src-tauri/src/managed_agents/runtime.rs`;
- frontend lifecycle actions:
  `desktop/src/features/agents/lib/managedAgentControlActions.ts`;
- native runtime: `crates/buzz-agent`;
- Sprig dispatch: `crates/sprig/src/main.rs`;
- upstream Kubernetes reference: `crates/buzz-backend-kubernetes`.

HyperCLI:

- hosted ACP source and upstream pin: `buzz-acp`;
- provider translation: `buzz-backend-provider/src/lib.rs`;
- typed launch rendering: `rs-sdk/src/types.rs`;
- golden contract: `tests/fixtures/buzz-launch-contract.json`;
- provider protocol tests: `buzz-backend-provider/tests/protocol.rs`.

HyperClaw backend and images:

- canonical backend contract: `backend/agents/launch_contract.py`;
- image definitions and initialization: this directory;
- image contract tests: `test_*.py` and parent smoke/CI tests.
