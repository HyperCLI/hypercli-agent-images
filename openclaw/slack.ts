import fs from "node:fs"

type ConfigObject = Record<string, unknown>

const env = process.env
const configPath = env.CONFIG_PATH

if (!configPath) throw new Error("CONFIG_PATH is required")

const config = JSON.parse(fs.readFileSync(configPath, "utf8")) as ConfigObject

function asRecord(value: unknown): ConfigObject | undefined {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return undefined
  return value as ConfigObject
}

// The disable path only tears down what the enable path writes: a relay
// channel whose auth token references HYPER_AGENTS_API_KEY. Hand-written or
// otherwise foreign slack configs survive an explicit disable untouched.
function isHostedSlackRelayConfig(slack: unknown): boolean {
  const channel = asRecord(slack)
  if (!channel || channel.mode !== "relay") return false
  const authToken = asRecord(asRecord(channel.relay)?.authToken)
  return authToken?.id === "HYPER_AGENTS_API_KEY"
}

// HYPER_SLACK_APP_ENABLED is a launch-env contract owned by the ts-sdk, which
// writes exactly "1" (enable) or "0" (disable). Anything else — unset, empty,
// legacy boolean spellings — is a no-op and leaves the retained config alone.
const flag = (env.HYPER_SLACK_APP_ENABLED ?? "").trim().toLowerCase()

if (flag === "1") {
  const relayUrl = (env.HYPER_SLACK_RELAY_URL ?? "").trim()
  const gatewayId = (env.HYPER_SLACK_GATEWAY_ID ?? "").trim()
  const apiUrl = (env.HYPER_SLACK_API_URL ?? "").trim()
  const agentsApiKey = (env.HYPER_AGENTS_API_KEY ?? "").trim()
  // Gates run BEFORE any write: the ts-sdk supplies all four companions
  // atomically, so a missing one means a broken launch env — fail the boot
  // loudly instead of persisting a half-reconciled config.
  const missing: string[] = []
  if (!relayUrl) missing.push("HYPER_SLACK_RELAY_URL")
  if (!gatewayId) missing.push("HYPER_SLACK_GATEWAY_ID")
  if (!apiUrl) missing.push("HYPER_SLACK_API_URL")
  if (!agentsApiKey) missing.push("HYPER_AGENTS_API_KEY")
  if (missing.length > 0) {
    console.error(`[openclaw] HYPER_SLACK_APP_ENABLED=1 requires ${missing.join(", ")}`)
    process.exit(1)
  }

  // Env is authoritative: channels.slack is fully replaced, never merged with
  // the retained config, so stale relay state cannot linger across boots.
  const channels = (config.channels ||= {}) as ConfigObject
  channels.slack = {
    enabled: true,
    mode: "relay",
    replyToMode: "all",
    replyToModeByChatType: { direct: "off" },
    botToken: { source: "env", provider: "default", id: "SLACK_BOT_TOKEN" },
    relay: {
      url: relayUrl,
      authToken: { source: "env", provider: "default", id: "HYPER_AGENTS_API_KEY" },
      gatewayId,
    },
  }
  const messages = (config.messages ||= {}) as ConfigObject
  messages.statusReactions = { enabled: true }
  const plugins = (config.plugins ||= {}) as ConfigObject
  const entries = (plugins.entries ||= {}) as ConfigObject
  const slackEntry = (entries.slack ||= {}) as ConfigObject
  slackEntry.enabled = true
}

if (flag === "0") {
  // Symmetric teardown: drop everything the enable path writes, but only when
  // channels.slack is recognizably the hosted relay config.
  const channels = asRecord(config.channels)
  if (channels && isHostedSlackRelayConfig(channels.slack)) {
    delete channels.slack
    const entries = asRecord(asRecord(config.plugins)?.entries)
    if (entries) delete entries.slack
    const messages = asRecord(config.messages)
    if (messages) delete messages.statusReactions
  }
}

// Atomic write: render to a sibling tmp file carrying the destination's
// existing mode, then rename over the target so readers never see a partial
// file.
const rendered = JSON.stringify(config, null, 2) + "\n"
const tmpPath = `${configPath}.tmp`
const existingMode = fs.statSync(configPath).mode & 0o777
fs.writeFileSync(tmpPath, rendered, { mode: existingMode })
fs.renameSync(tmpPath, configPath)
