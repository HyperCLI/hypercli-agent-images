# HyperCLI agent images

## Coding Agents

`coding/` contains the product-specific images used by hosted coding agents. Each
provider has its own Dockerfile and test:

```text
coding/
├── acp-base/
├── buzz-agent/
├── opencode/
├── codex/
├── claude/
├── goose/
└── kimi-code/
```

Build the canonical agent base, the coding ACP base, then one provider image:

```bash
docker build \
  --build-arg HYPERCLI_REF=main \
  -t hypercli-agent-base \
  -f base/Dockerfile base

docker build \
  --build-arg HYPERCLI_AGENT_BASE_IMAGE=hypercli-agent-base \
  -t hypercli-acp-base \
  -f coding/acp-base/Dockerfile coding

docker build \
  --build-arg HYPER_ACP_BASE_IMAGE=hypercli-acp-base \
  -t hypercli-opencode \
  -f coding/opencode/Dockerfile coding
```

Run the matching Python contracts:

```bash
python3 base/test.py hypercli-agent-base
python3 coding/acp-base/test.py hypercli-acp-base
python3 coding/opencode/test.py hypercli-opencode
```

The six public runtime images are:

| Directory | Image | ACP child | Authentication |
| --- | --- | --- | --- |
| `buzz-agent` | `hypercli-buzz-agent` | `buzz-agent` | Scoped HyperCLI OpenAI-compatible chat inference plus Buzz MCP/skills |
| `opencode` | `hypercli-opencode` | `opencode acp` | OpenCode login or seeded HyperCLI Anthropic provider |
| `codex` | `hypercli-codex` | `codex-acp` | Codex API key or device login |
| `claude` | `hypercli-claude` | `claude-agent-acp` | Claude subscription, Console, or SSO |
| `goose` | `hypercli-goose` | `goose acp` | Seeded HyperCLI provider with OpenAI and Anthropic aliases plus Goose MCP/skills |
| `kimi-code` | `hypercli-kimi-code` | `kimi acp` | Upstream Moonshot login |

The canonical `hypercli-agent-base` installs Python, `hyper` with all CLI
extras in its own `/opt/hypercli-cli/venv`, build tools, `jq`, `rg`
(ripgrep), passwordless sudo for `node`, and HyperCLI skills. It does not
inherit from or contain OpenClaw.
`HYPERCLI_REF` defaults to `main`; `HYPERCLI_SHA` is an opt-in exact override.

`hypercli-acp-base` adds `acp`, the Buzz plugin, the pinned Buzz Sprig
multicall binary, and the shared coding entrypoint. Provider images add only
their selected runtime CLI and provider-specific configuration.

The persistent sync root remains `/home/node`, and HyperCLI Workspace
projections remain under `/home/node/shared`. The main process initializes the
workspace directly under `/home/node`. It seeds only missing files, so restored
user content is preserved.

The workspace contains standard directories and runtime skill links. The
Buzz CLI skill is installed only for native `buzz-agent` images or explicit
`acp plugin buzz` launches. `base_prompt.md` remains compiled into `acp` and
the Buzz adapter; it is not copied into the image workspace.

The launch control plane injects the agent identity, relay URL, and owner-signed
authorization tag. It overrides the default `sleep infinity` command with
`acp`; shell launches retain the same image and persistent home.

CI publishes `hypercli-agent-base`, resolves it to an immutable digest, builds
`hypercli-acp-base` from that digest, then builds and tests each provider from
the ACP base. The OpenCode job also runs the synthetic offline ACP regression
before promotion.

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
depend on runtime lazy installs. The image ships a checked-in Mem0 config at
`/home/hermes/.hermes/mem0.json`: Mem0 OSS mode, an OpenAI-style LLM provider
set to `default-anthropic`, an OpenAI-style embedder set to
`qwen3-embedding-4b` with 2560-dimensional vectors, and local Qdrant storage
under `/home/hermes/.hermes/mem0_qdrant`. Launch credentials are projected
through the managed runtime environment, not written into the durable Mem0
config.

## Security boundary

Coding images intentionally grant passwordless sudo to the `node` user. Hosted
ACP permission behavior is controlled by `HYPER_ACP_PERMISSION_MODE`;
`default` preserves runtime permission handling, while `auto` or
`bypass-permissions` approves inside the pod. The effective boundary is
therefore the per-agent namespace, filesystem/persistence scope, resource
limits, and scoped runtime credentials. The current per-agent NetworkPolicy
restricts ingress but does not restrict egress.

Lagoon stores caller-supplied runtime environment in the per-agent `reef-env`
Kubernetes Secret, but the current backend also persists those raw values in
ordinary launch JSON and exposes env/exec APIs. Do not treat these images or the
unsigned provider test release as a production-safe secret boundary until the
backend moves launch secrets to encrypted/external references and narrows those
read/exec capabilities.
