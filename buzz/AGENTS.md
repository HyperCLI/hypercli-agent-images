# Buzz Image Maintainer Guide

This directory builds the hosted Buzz coding-agent images. Read `README.md`
before changing the provider contract, image entrypoints, runtime commands, or
workspace initialization.

## Sources Of Truth

- `README.md` is the human architecture and lifecycle reference for these
  images.
- `nest/AGENTS.md` is shipped runtime content. It must remain byte-for-byte
  equal to Buzz Desktop's pinned `nest_agents.md`.
- `SKILLS.md` is the runtime-facing index for installed HyperCLI skills.
- `hypercli/hyper-acp` owns hosted startup. It launches the copied
  `hypercli/hyper-acp/plugins/buzz-acp` plugin for ACP framing, relay
  behavior, prompt transport, mention matching, and the shared reply guard.
  The Buzz plugin manifest pins the unmodified upstream Buzz crates it consumes.
- The HyperCLI provider owns translation from Buzz's portable launch request to
  the HyperCLI deployments API.
- HyperClaw/Lagoon owns remote scheduling and container lifecycle.

Do not duplicate these contracts in another Markdown file. Update `README.md`
and the executable tests together when the contract changes.

## Change Rules

- Track upstream Buzz behavior and keep the hosted delta in
  `hypercli/hyper-acp/plugins/buzz-acp` minimal. Advance its documented
  upstream pin only after reviewing the complete upstream `buzz-acp` diff and
  running its tests.
- Never invent a Desktop provider operation. Protocol v1 supports only `info`
  and `deploy`.
- Preserve the resolved `launch` block. Do not reconstruct prompt, access,
  runtime, or policy from unrelated display fields.
- Keep runtime commands and prompt transports explicit in the runtime matrix.
- Keep provider-owned identity, relay, authorization, reply, mention, and
  workspace variables non-overridable by user environment.
- Keep hosted deployments `restart: false`; normal `hyper-acp` exit must remain
  terminal for the pod.
- Do not convert ACP activity or thinking output into a final Buzz message.
- Do not replace user-managed files or links under `/home/node/.buzz`.
- Do not put secrets, raw provider requests, auth tags, private keys, or
  terminal transcripts in logs, fixtures, or documentation.

## Required Verification

At minimum, run the image contract test for every touched runtime. Changes to
provider or lifecycle behavior also require the sanitized provider-wire and
deployment contract tests in the parent repositories. The checks must cover:

1. Exact command, arguments, MCP command, environment, and prompt transport.
2. Byte equality between `nest/AGENTS.md` and pinned Buzz `nest_agents.md`.
3. Prompt delivery exactly once.
4. Bounded reply-guard behavior.
5. Independent text-mention matching and author authorization.
6. Persistent user-managed workspace files across initialization.
