# HyperCLI agent images

## Coding agents

`coding-agents/Dockerfile` is the shared image definition for HyperCLI-hosted
Buzz coding runtimes. Its `RUNTIME_IMAGE` defaults to the CI-gated public HyperCLI
OpenClaw image, so the carrier inherits the exact Python HyperCLI installation
and operational packages already exercised by the OpenClaw image gates. CI
should override it with the immutable digest of the OpenClaw image it has
already tested:

```bash
docker build \
  --target runtime-base \
  --build-arg RUNTIME_IMAGE=git.nedos.co/hypercli/hypercli-openclaw@sha256:... \
  -t registry.example/hypercli-coding-base:BUZZ_SHA \
  coding-agents
```

The carrier removes the inherited `/app` OpenClaw runtime, CLI link, state
template, entrypoint, and healthcheck. It then adds the pinned Buzz Sprig
multicall binary, `tini`, passwordless sudo for `node`, and the `/home/node`
runtime/persistence contract. OpenClaw is lineage, not a second runtime inside
the coding images.

The generic images keep both home and working directory at `/home/node`, so
terminal sessions open at the persistent sync root. Shared workspaces remain
projected under `/home/node/workspaces`.

Build one of the immutable runtime targets:

```bash
docker build --target opencode -t hypercli-opencode coding-agents
docker build --target codex -t hypercli-codex coding-agents
docker build --target claude-code -t hypercli-claude-code coding-agents
docker build --target goose -t hypercli-goose coding-agents
docker build --target kimi-code -t hypercli-kimi-code coding-agents
```

Those five targets remain generic coding-runtime images. Buzz-hosted launches
use the corresponding specialized targets:

```bash
docker build --target buzz-opencode -t hypercli-buzz-opencode coding-agents
docker build --target buzz-codex -t hypercli-buzz-codex coding-agents
docker build --target buzz-claude-code -t hypercli-buzz-claude coding-agents
docker build --target buzz-goose -t hypercli-buzz-goose coding-agents
docker build --target buzz-kimi-code -t hypercli-buzz-kimi-code coding-agents
```

Each specialized target is a thin layer on its generic counterpart. It retains
`HOME=/home/node`, native runtime authentication/configuration, and the
`/home/node/workspaces` HyperCLI projection. Its wrapper creates the stock Buzz
nest at `/home/node/.buzz`, enters that directory, and then invokes the generic
runtime entrypoint. As a result, `buzz-acp` passes `/home/node/.buzz` as the ACP
session working directory without treating the projected HyperCLI workspaces as
the Buzz nest.

The nest is restored with the rest of `/home/node` and contains:

```text
/home/node/.buzz/
├── AGENTS.md
├── GUIDES/
├── RESEARCH/
├── PLANS/
├── WORK_LOGS/
├── OUTBOX/
├── REPOS/
├── .scratch/
└── .agents/skills/buzz-cli/SKILL.md
```

`AGENTS.md` and the Buzz CLI skill come directly from the Buzz source pinned by
`BUZZ_COMMIT`; the image does not carry a separately duplicated base prompt.
The wrapper only seeds missing files and links. It preserves user-managed files,
rejects a symlinked nest root, applies owner-only nest permissions, and creates
the stock project-local Goose, Claude, and Codex skill links. The Claude
specialized image additionally creates `CLAUDE.md -> AGENTS.md` unless a real
user file or another link already occupies that path.

For CI jobs that build the targets separately, publish the shared carrier once:

```bash
docker build \
  --target runtime-base \
  --build-arg RUNTIME_IMAGE=git.nedos.co/hypercli/hypercli-openclaw@sha256:... \
  -t registry.example/hypercli-coding-base:BUZZ_SHA \
  coding-agents
docker push registry.example/hypercli-coding-base:BUZZ_SHA
```

Resolve that tag to a digest, then pass the immutable reference to every target
build:

```bash
docker build \
  --target opencode \
  --build-arg CODING_AGENT_BASE_IMAGE=registry.example/hypercli-coding-base@sha256:... \
  -t hypercli-opencode \
  coding-agents
```

With the default `CODING_AGENT_BASE_IMAGE=runtime-base`, a standalone build
uses the in-file carrier layered on
`ghcr.io/hypercli/hypercli-openclaw:prod`. The Cargo registry, Cargo git, and
target directories also use locked BuildKit cache mounts; those caches help
repeated builds on one builder, but they are not a substitute for the two
digest-pinned carriers—OpenClaw lineage and the shared coding base—across
isolated CI workers.

The baked ACP child commands and authentication boundaries are:

| Target | ACP child | Default configuration/authentication |
| --- | --- | --- |
| `opencode` | `opencode acp` | Seeds a HyperCLI Anthropic provider using `HYPER_AGENTS_API_KEY` |
| `codex` | `codex-acp` | Retains native Codex API/device authentication |
| `claude-code` | `claude-agent-acp` | Retains native Claude subscription/Console/SSO authentication |
| `goose` | `goose acp` | Seeds a HyperCLI Anthropic provider using `HYPER_AGENTS_API_KEY` |
| `kimi-code` | `kimi acp` | Retains Moonshot's upstream Kimi Code login/service |

All targets build the Sprig multicall binary from the full commit in
`BUZZ_COMMIT`. `buzz-acp`, `buzz-dev-mcp`, and `buzz` are links to that exact
binary, so tests and production use the same Buzz ACP client.

Every image uses `tini` as PID 1 and defaults to `sleep infinity`, making it
directly usable through authenticated shell/exec. Lagoon's workspace init
container invokes `hyper workspaces sync` directly; it does not route init work
through either the generic or Buzz entrypoint. Keeping the Docker `WORKDIR` at
`/home/node` is therefore intentional: a newly mounted persistent home does not
contain `.buzz` until the main Buzz wrapper initializes it.

Buzz relay attachment must be selected by the launch control plane using a
`buzz-*` image. The launch replaces the default container arguments with
`/usr/local/bin/buzz-acp` and injects:

```text
BUZZ_PRIVATE_KEY=<unique agent nsec or hex secret>
NOSTR_PRIVATE_KEY=<the same unique agent nsec>
BUZZ_RELAY_URL=wss://buzz.example.com
BUZZ_AUTH_TAG=<owner-signed NIP-OA auth tag JSON>
```

`BUZZ_PRIVATE_KEY` is consumed by `buzz-acp`; `NOSTR_PRIVATE_KEY` is separately
consumed by Buzz git/signing tools and is not an alias. `BUZZ_AUTH_TAG` is used
for owner-attested admission. Direct membership and other response modes are
also valid, so the image does not impose credential policy in shell.
`BUZZ_ACP_CHANNELS` is optional; the default subscription listens for mentions
across authorized channels.

Generate the agent keypair and owner attestation in the trusted launch control
plane, then inject them through the existing Lagoon secret environment. Do not
generate the key only inside the pod: its pubkey cannot be owner-authorized
before connection, and replacing a restored key would create a different Buzz
agent identity.

After building an image, check its installed contract with:

```bash
coding-agents/base-sanity-check.sh hypercli-coding-base
coding-agents/sanity-check.sh hypercli-opencode opencode
coding-agents/sanity-check.sh hypercli-codex codex
coding-agents/sanity-check.sh hypercli-claude-code claude-code
coding-agents/sanity-check.sh hypercli-goose goose
coding-agents/sanity-check.sh hypercli-kimi-code kimi-code
coding-agents/buzz-sanity-check.sh hypercli-buzz-opencode opencode
coding-agents/buzz-sanity-check.sh hypercli-buzz-codex codex
coding-agents/buzz-sanity-check.sh hypercli-buzz-claude claude-code
coding-agents/buzz-sanity-check.sh hypercli-buzz-goose goose
coding-agents/buzz-sanity-check.sh hypercli-buzz-kimi-code kimi-code
```

The shared-base gate owns UID 1000, `/home/node`, passwordless sudo, `tini`,
HyperCLI, Sprig, and common tooling. Thin-runtime gates test only the package
and ACP behavior they add. Each runtime gate also verifies its advertised ACP
auth method IDs and its pinned CLI's native unauthenticated login/status
surface without starting or persisting a real account login.

OpenCode and Goose seed their HyperCLI Anthropic-provider configuration into
the persistent home only when the user has not already supplied one. Kimi Code
keeps its upstream Moonshot login/configuration path. Codex and Claude Code
retain their native vendor authentication paths. These runtime-owned files stay
under `/home/node`; the Buzz wrapper does not relocate them into the nest.

Existing CI launches all five generic images through HyperClaw and Lagoon,
validates their
runtime/auth discovery, and promotes the tested content to public GHCR
full-commit and `latest` tags. OpenCode and Goose additionally run a real
HyperCLI Anthropic-native tool-use inference. The separate provider gate is
configured to use the public full-commit OpenCode tag and validate provider
create/retry plus the deployed environment. The job must pass before it is
release evidence. It does not send a prompt through a Buzz relay or exercise an
official Desktop client.

Before publishing the `buzz-*` variants, CI must run
`coding-agents/buzz-sanity-check.sh` for all five targets in addition to each
generic runtime contract. The specialized gate covers nest initialization,
mounted-home persistence, no-clobber behavior, canonical templates and links,
and symlink-root rejection; it does not constitute relay or Desktop E2E.

For reproducible launches, use a full-commit tag or resolved digest. `latest`
is the provider's user-facing convenience default after promotion, not an
immutable deployment reference.

## Security boundary

Coding images intentionally grant passwordless sudo to the `node` user and
`buzz-acp` currently auto-approves ACP permission requests. The effective
boundary is therefore the per-agent namespace, filesystem/persistence scope,
resource limits, and scoped runtime credentials. The current per-agent
NetworkPolicy restricts ingress but does not restrict egress.

Lagoon stores caller-supplied runtime environment in the per-agent `reef-env`
Kubernetes Secret, but the current backend also persists those raw values in
ordinary launch JSON and exposes env/exec APIs. Do not treat these images or the
unsigned provider test release as a production-safe secret boundary until the
backend moves launch secrets to encrypted/external references and narrows those
read/exec capabilities.
