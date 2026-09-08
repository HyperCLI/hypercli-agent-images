# Coding Image Maintainer Guide

This directory builds hosted coding-agent images. Read `README.md` before
changing the provider contract, image entrypoints, runtime commands, or
workspace initialization.

## Sources Of Truth

- `README.md` is the human architecture and lifecycle reference for these
  images.
- Plain ACP base prompt delivery is owned by `hypercli/hyper-acp` and injected
  into `session/new` from the compiled generic prompt unless `HYPER_ACP_*`
  env/file overrides say otherwise. Buzz provider launches keep their
  Buzz-specific `BUZZ_ACP_*` prompt contract and use the Buzz plugin's compiled
  base prompt unless the caller explicitly supplies a Buzz base-prompt file.
- `SKILLS.md` is the runtime-facing index for installed HyperCLI skills.
- `hypercli/hyper-acp` owns hosted ACP startup. Plain ACP launches run
  `acp` with `HYPER_ACP_AGENT_COMMAND` and `HYPER_ACP_AGENT_ARGS`.
  Buzz/Nostr launches run `acp plugin buzz`, which links the copied
  `hypercli/hyper-acp/plugins/buzz` implementation for relay behavior, prompt
  transport, mention matching, and the shared reply guard. The Buzz plugin
  manifest pins the unmodified upstream Buzz crates it consumes.
- The HyperCLI provider owns translation from Buzz's portable launch request to
  the HyperCLI deployments API.
- HyperClaw/Lagoon owns remote scheduling and container lifecycle.

Do not duplicate these contracts in another Markdown file. Update `README.md`
and the executable tests together when the contract changes.

## Change Rules

- Track upstream Buzz behavior and keep the hosted delta in
  `hypercli/hyper-acp/plugins/buzz` minimal. Advance its documented
  upstream pin only after reviewing the complete upstream `buzz-acp` diff and
  running its tests.
- Never invent a Desktop provider operation. Protocol v1 supports only `info`
  and `deploy`.
- Preserve the resolved `launch` block. Do not reconstruct prompt, access,
  runtime, or policy from unrelated display fields.
- Keep runtime commands and prompt transports explicit in the runtime matrix.
- Keep provider-owned identity, relay, authorization, reply, mention, and
  workspace variables non-overridable by user environment.
- Keep Buzz provider deployments `restart: false`; normal
  `acp plugin buzz` exit must remain terminal for the pod.
- Do not convert ACP activity or thinking output into a final Buzz message.
- Do not replace user-managed files or links under `/home/node`.
- Do not put secrets, raw provider requests, auth tags, private keys, or
  terminal transcripts in logs, fixtures, or documentation.

## Required Verification

At minimum, run the image contract test for every touched runtime. Changes to
provider or lifecycle behavior also require the sanitized provider-wire and
deployment contract tests in the parent repositories. The checks must cover:

1. Exact command, arguments, MCP command, environment, and prompt transport.
2. Runtime prompt installation from the pinned HyperACP base prompt.
3. Prompt delivery exactly once.
4. Bounded reply-guard behavior.
5. Independent text-mention matching and author authorization.
6. Persistent user-managed workspace files across initialization.
