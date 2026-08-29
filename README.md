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
  -t hypercli-acp-base \
  -f buzz/base/Dockerfile buzz

docker build \
  --build-arg HYPERCLI_ACP_BASE_IMAGE=hypercli-acp-base \
  -t hypercli-buzz-opencode \
  -f buzz/opencode/Dockerfile buzz
```

Run the matching Python contracts:

```bash
python3 buzz/base/test.py hypercli-acp-base
python3 buzz/opencode/test.py hypercli-buzz-opencode
```

The six public runtime images are:

| Directory | Image | ACP child | Authentication |
| --- | --- | --- | --- |
| `buzz-agent` | `hypercli-buzz-agent` | `buzz-agent` | Scoped HyperCLI Anthropic-compatible inference plus Buzz MCP/skills |
| `opencode` | `hypercli-buzz-opencode` | `opencode acp` | OpenCode login or seeded HyperCLI Anthropic provider |
| `codex` | `hypercli-buzz-codex` | `codex-acp` | Codex API key or device login |
| `claude` | `hypercli-buzz-claude` | `claude-agent-acp` | Claude subscription, Console, or SSO |
| `goose` | `hypercli-buzz-goose` | `goose acp` | Seeded HyperCLI provider with OpenAI and Anthropic aliases plus Goose MCP/skills |
| `kimi-code` | `hypercli-buzz-kimi-code` | `kimi acp` | Upstream Moonshot login |

The common carrier installs Python, `hyper` with all CLI extras, build tools,
`jq`, `rg` (ripgrep), passwordless sudo for `node`, and Buzz's pinned Sprig
multicall binary. It does not inherit from or contain OpenClaw.

The persistent sync root remains `/home/node`, and HyperCLI Workspace
projections remain under `/home/node/shared`. The main process reconciles
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

The OpenClaw and Hermes images share a general coding-tool floor: Python and
native build tools, Node/npm/npx, pinned Corepack/pnpm/Yarn, media/PDF tools,
editors, archives, HyperCLI with all extras, and passwordless sudo for their
actual runtime users. Runtime-specific applications and plugins remain separate.

Both runtimes clone HyperCLI into `/opt/hypercli`, including the bundled
`/opt/hypercli/skills` library. OpenClaw synchronizes those skills into its
state directory on launch. Hermes seeds missing skills into
`/home/hermes/.hermes/skills` and also registers `/opt/hypercli/skills` as
`skills.external_dirs`, so the immutable image skills are visible as an
externally owned source.

Coding images keep their retained runtime root mounted as the runtime user's
home directory and reserve `$HOME/shared` for HyperCLI Workspace projections.
`shared/` lives on the retained PVC, so restarted containers can still see it,
but SDK launch defaults exclude `shared/**` from Reef/S3 backup. Workspaces
are boot-materialized and can drift during sessions; backing them up as normal
home state makes restores stale and unnecessarily large.

OpenClaw and Hermes seed the Anthropic-route HyperCLI aliases into their
runtime config and boot with `default-anthropic`. That default is a stable
container contract: the backend can retarget it without breaking existing
containers. Today the image aliases resolve as:

| Alias | Current target | Notes |
| --- | --- | --- |
| `default-anthropic` | `kimi-k3-anthropic` | Image default, Anthropic Messages route |
| `coding-anthropic` | `kimi-k3-anthropic` | Stable coding alias, Anthropic Messages route |
| `kimi-k3-anthropic` | `kimi-k3-anthropic` | Pinned Kimi K3 Anthropic Messages route |
| `kimi-k2.6-anthropic` | `kimi-k2.6-anthropic` | Pinned Kimi K2.6 Anthropic Messages route |
| `kimi-k2.5-anthropic` | `kimi-k2.6-anthropic` | Legacy compatibility alias |

The authoritative alias map lives in
[`pulumi-api-k8s/gpus.yaml`](/home/ubuntu/dev/hyperclaw-backend/pulumi-api-k8s/gpus.yaml).
Image configs duplicate the public names so runtime UIs can list and select
them before the first model request.

For agent runtimes and tool-calling workloads, prefer `-anthropic` aliases.
They use the Anthropic Messages route and are the expected surface for the best
tool-calling behavior.

OpenCode boots with `coding-anthropic`, and its seeded config includes
both route families: `default`, `coding`, `kimi-k3`, `kimi-k2.6`, `kimi-k2.5`,
and the matching `-anthropic` aliases. Keep the `-anthropic` aliases as the
default path for hosted coding work; the non-suffixed names remain available
for OpenCode flows that expect the OpenAI-compatible model names.

OpenCode also seeds remote MCP servers for HyperCLI product tools and
Mintlify docs search. The image entrypoint sets `HYPER_MCP_API_KEY` from
`HYPER_API_KEY` when a user supplies a long-term key, otherwise from the
backend-injected `HYPER_AGENTS_API_KEY`. The OpenCode config uses
`HYPER_MCP_API_KEY` only for MCP headers; model inference remains explicitly
keyed by `HYPER_AGENTS_API_KEY`. The product MCP URL defaults to
`${HYPER_API_BASE}/api/mcp` and can be overridden with
`HYPER_OPENCODE_MCP_URL`.

OpenClaw exposes vector-backed memory search as `memorySearch`, using the
HyperCLI embeddings route `qwen3-embedding-4b` at
`${HYPER_AGENTS_API_BASE}/v1`. Hermes uses its native external memory provider
slot and boots with `memory.provider: mem0`. The image bakes `mem0ai` and
`qdrant-client` into the Hermes venv, so the default memory provider does not
depend on runtime lazy installs. The Hermes entrypoint seeds
`/home/hermes/.hermes/mem0.json` only when missing, in Mem0 OSS mode, with an
OpenAI-style LLM provider set to `default-anthropic`, an OpenAI-style embedder
set to `qwen3-embedding-4b` with 2560-dimensional vectors, and local Qdrant
storage under `/home/hermes/.hermes/mem0_qdrant`. Launch credentials are
projected through the managed runtime environment, not written into the durable
Mem0 config.

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
