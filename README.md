# HyperCLI agent images

## Coding agents

`coding-agents/Dockerfile` is the shared image definition for the Buzz-hosted
coding runtimes. Its `RUNTIME_IMAGE` defaults to the CI-gated public HyperCLI
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

The default home and working directory are both `/home/node`, so terminal
sessions open at the persistent sync root. Shared workspaces remain projected
under `/home/node/workspaces`.

Build one of the immutable runtime targets:

```bash
docker build --target opencode -t hypercli-opencode coding-agents
docker build --target codex -t hypercli-codex coding-agents
docker build --target claude-code -t hypercli-claude-code coding-agents
```

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

The baked ACP child commands are:

| Target | ACP child |
| --- | --- |
| `opencode` | `opencode acp` |
| `codex` | `codex-acp` |
| `claude-code` | `claude-agent-acp` |

All targets build the Sprig multicall binary from the full commit in
`BUZZ_COMMIT`. `buzz-acp`, `buzz-dev-mcp`, and `buzz` are links to that exact
binary, so tests and production use the same Buzz ACP client.

The image uses `tini` as PID 1 and defaults to `sleep infinity`, making it
directly usable through authenticated shell/exec. Lagoon's workspace init
container invokes `hyper workspaces sync` directly; it does not route init work
through the main image entrypoint.

Buzz relay attachment is selected by the launch control plane. It replaces the
default container arguments with `/usr/local/bin/buzz-acp` and injects:

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
```

The shared-base gate owns UID 1000, `/home/node`, passwordless sudo, `tini`,
HyperCLI, Sprig, and common tooling. Thin-runtime gates test only the package
and ACP behavior they add. Each runtime gate also verifies its advertised ACP
auth method IDs and its pinned CLI's native unauthenticated login/status
surface without starting or persisting a real account login.
