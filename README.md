# HyperCLI agent images

## Buzz coding agents

`buzz/` contains the product-specific images used by hosted Buzz agents. Each
provider has its own Dockerfile and test:

```text
buzz/
├── base/
├── opencode/
├── codex/
├── claude/
├── goose/
└── kimi-code/
```

Build the common Node 24 carrier, then one provider image:

```bash
BUZZ_SOURCE=/path/to/hyperclaw-backend/buzz
docker build \
  --build-context "buzz-source=${BUZZ_SOURCE}" \
  --build-arg "BUZZ_COMMIT=$(git -C "${BUZZ_SOURCE}" rev-parse HEAD)" \
  --build-arg HYPERCLI_REF=<full-hypercli-commit> \
  -t hypercli-buzz-base \
  -f buzz/base/Dockerfile buzz

docker build \
  --build-arg BUZZ_BASE_IMAGE=hypercli-buzz-base \
  -t hypercli-buzz-opencode \
  -f buzz/opencode/Dockerfile buzz
```

Run the matching Python contracts:

```bash
python3 buzz/base/test.py hypercli-buzz-base
python3 buzz/opencode/test.py hypercli-buzz-opencode
```

The five public runtime images are:

| Directory | Image | ACP child | Authentication |
| --- | --- | --- | --- |
| `opencode` | `hypercli-buzz-opencode` | `opencode acp` | OpenCode login or seeded HyperCLI Anthropic provider |
| `codex` | `hypercli-buzz-codex` | `codex-acp` | Codex API key or device login |
| `claude` | `hypercli-buzz-claude` | `claude-agent-acp` | Claude subscription, Console, or SSO |
| `goose` | `hypercli-buzz-goose` | `goose acp` | Seeded HyperCLI Anthropic provider |
| `kimi-code` | `hypercli-buzz-kimi-code` | `kimi acp` | Upstream Moonshot login |

The common carrier installs Python, `hyper` with all CLI extras, build tools,
`jq`, `rg` (ripgrep), passwordless sudo for `node`, and Buzz's pinned Sprig
multicall binary. It does not inherit from or contain OpenClaw.

The persistent sync root remains `/home/node`, and HyperCLI Workspace
projections remain under `/home/node/workspaces`. The main process reconciles
the stock Buzz nest after that home is mounted, then runs from
`/home/node/.buzz`. It seeds only missing files, so restored user content is
preserved.

The nest contains the canonical Buzz `AGENTS.md`, standard directories, the
Buzz CLI skill, and the standard runtime skill links. Claude additionally gets
`CLAUDE.md -> AGENTS.md`. `base_prompt.md` remains compiled into `buzz-acp` and
is not copied into the image or nest.

The launch control plane injects the agent identity, relay URL, and owner-signed
authorization tag. It overrides the default `sleep infinity` command with
`buzz-acp`; shell launches retain the same image and persistent home.

CI publishes the common carrier once, resolves it to an immutable digest, then
builds and tests each provider independently. The OpenCode job also runs the
synthetic offline ACP regression before promotion.

## OpenClaw

The independently maintained `openclaw/` image remains the OpenClaw runtime.
It is not a base for the Buzz coding-agent images.

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
