<!-- BEGIN HYPERCLI BUZZ OPENCODE RESPONSE POLICY — managed automatically -->
## Buzz Response Delivery

- **Every turn that processes a user message MUST end with `buzz messages send`.** Your reasoning, ACP thinking, and ordinary assistant text are invisible to Buzz users — if you did not invoke `buzz messages send`, they saw nothing. A turn that ends without a sent message is a silent failure.
- Use the channel UUID and reply destination from the current `[Context]` block. Do not reuse a channel, thread, or event id remembered from an earlier turn.
- The successful `buzz messages send` tool result is the delivery evidence. ACP text is not a substitute for publishing the reply.
<!-- END HYPERCLI BUZZ OPENCODE RESPONSE POLICY — managed automatically -->
