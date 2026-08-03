# Buzz Desktop Provider Contract

This document records the part of Buzz Desktop that HyperCLI-hosted ACP
runtimes must match. It is a source map, not a second specification. When the
pinned Buzz source changes, re-check these paths before changing the provider
or images.

## Ownership boundary

Buzz Desktop owns the persona, agent identity, relay credentials, effective
prompt/model/provider, access policy, channel membership, and the choice of
backend provider. HyperCLI owns the remote deployment created from that
request. The runtime image owns only process setup and the files needed by the
selected coding harness.

The desktop serializes the provider request in
`desktop/src-tauri/src/commands/agents_deploy.rs`:

- `deploy_payload_json` carries identity, relay URL, private key, display
  metadata, model/provider/prompt, parallelism, `respond_to`, allowlist, user
  environment, and the resolved `launch` block.
- `build_launch_block` carries the resolved harness command/arguments and the
  desktop policy environment, including the composed system prompt, model,
  owner, timeouts, team instructions, and ACP pool size.
- Legacy top-level fields are display/bookkeeping compatibility. The resolved
  `launch` block is the executable contract.

The provider must not infer a different prompt, access mode, or runtime from
unrelated UI fields. HyperCLI selects its canonical image and ACP child from
the basename of `agent.launch.command`; `agent.agent_command` is only the
compatibility fallback when a legacy payload has no `launch` block. See
`buzz/RUNTIME.md` for the matrix.

## Provider process protocol

`desktop/src-tauri/src/managed_agents/backend.rs` is authoritative:

1. The desktop stages one immutable copy of the provider binary.
2. It starts the binary with no arguments, writes one JSON object plus newline
   to stdin, closes stdin, and reads one JSON object from stdout.
3. It invokes `info` with a 10-second timeout and validates protocol version 1.
4. It invokes `deploy` on the same staged bytes with a 600-second timeout.
5. The deploy result must contain `agent_id`.

Protocol v1 has no generic provider `start`, `stop`, `delete`, `update`,
`exec`, `logs`, or `status` operation. UI actions with those names therefore
must not be assumed to invoke this provider binary. Hosted lifecycle actions
belong to the HyperCLI agents API/CLI until Buzz adds corresponding provider
operations.

The owner-signed `!shutdown` control message is not a provider RPC. `buzz-acp`
consumes it from the relay, performs its graceful shutdown sequence, and exits.
HyperCLI launches hosted Buzz deployments with `restart: false`, so that exit
leaves the pod terminal instead of restarting the harness. The portable
`launch` block has no restart field: this is provider-owned substrate policy.
A later explicit desktop Start invokes `deploy` again, allowing the provider to
start the stopped deterministic deployment.

Provider stdout is reserved for the JSON response. Diagnostics belong on
stderr and must not contain secrets. The desktop caps provider stdout at 1 MiB,
stderr at 64 KiB, rejects nonzero exits, and redacts request environment
secrets before surfacing provider errors.

## Definition to instance behavior

`desktop/src/features/agents/lib/instanceInputForDefinition.ts` establishes
the remote-provider create behavior:

- `spawnAfterCreate` is true.
- `startOnAppLaunch` is false.
- no local ACP, agent, or MCP process is spawned by the desktop.
- the provider choice and provider configuration are stored on the instance.
- definition environment is resolved at deploy time rather than copied into a
  new local runtime.

An already deployed remote instance is not automatically replaced when the
persona name, access policy, environment, or harness defaults change. Any
provider-owned launch value that must change requires a stop/redeploy through
HyperCLI. Tests must not claim that an edit hot-reloads the remote container.

## Message and reply behavior

`buzz-acp` connects the remote harness to the relay. The desktop does not
forward an ACP `agent_message_chunk` as the agent's final Buzz message. A
runtime publishes through `buzz messages send` or `buzz reactions add` (or the
equivalent registered MCP command). Activity/thinking output remains observer
telemetry.

HyperCLI enables the shared hosted reply guard with
`BUZZ_ACP_REQUIRE_REPLY=true`. On a genuine ACP `end_turn` without a publish
attempt, the adapter sends Buzz's canonical reminder in the same session, at
most twice, under the original hard deadline. Silence remains valid after the
second reminder.

The desktop's `respond_to` value is an author-authorization gate. Hosted text
mention fallback is separate: the provider always supplies
`BUZZ_ACP_DISPLAY_NAME` and enables `BUZZ_ACP_TEXT_MENTIONS` only for a
compatible display name. Text mention matching does not bypass owner-only or
allowlist authorization.

## Regression checklist

Changes to the provider, SDK launch types, ACP adapter, or images must retain:

1. A single immutable `info` then `deploy` provider exchange.
2. The exact resolved `launch.command`, `launch.args`, prompt, access policy,
   owner, and environment semantics from the desktop request.
3. No provider lifecycle RPCs invented outside protocol v1.
4. No conversion of ACP activity text into a Buzz final response.
5. Adapter-neutral reply-guard behavior and bounded retries.
6. Independent mention matching and author authorization.
7. Byte-for-byte preservation of user-managed `.buzz/AGENTS.md` on restart.
8. Hosted `restart: false` policy and real-entrypoint exit-code propagation, so
   a graceful `!shutdown` remains stopped until an explicit Start/Deploy.
