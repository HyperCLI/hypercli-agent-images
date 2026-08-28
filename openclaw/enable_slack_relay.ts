const fs = require("fs");

const HOSTED_RELAY_AUTH_TOKEN_ENV = "HYPER_AGENTS_API_KEY";
const env = process.env;
const configPath = env.CONFIG_PATH;

if (!configPath) {
  throw new Error("CONFIG_PATH is required");
}

const config = JSON.parse(fs.readFileSync(configPath, "utf8"));

function parseBoolean(name) {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return undefined;
  }

  switch (raw.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
    case "enabled":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
    case "disabled":
      return false;
    default:
      throw new Error(`${name} must be a boolean-like value`);
  }
}

function asObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  return value;
}

function ensureObject(parent, key) {
  const existing = asObject(parent[key]);
  if (existing) {
    return existing;
  }

  const next = {};
  parent[key] = next;
  return next;
}

function envSecretId(value) {
  const ref = asObject(value);
  if (!ref || ref.source !== "env") {
    return undefined;
  }
  return ref.id;
}

function readCsv(name) {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return [];
  }

  const seen = new Set();
  const values = [];
  for (const value of raw.split(",")) {
    const trimmed = value.trim();
    if (!trimmed || seen.has(trimmed)) {
      continue;
    }
    seen.add(trimmed);
    values.push(trimmed);
  }
  return values;
}

function readJsonObject(name) {
  const raw = env[name];
  if (raw === undefined || raw === "") {
    return undefined;
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new Error(`${name} must contain valid JSON`, { cause: error });
  }

  const object = asObject(parsed);
  if (!object) {
    throw new Error(`${name} must contain a JSON object`);
  }
  return object;
}

function readExistingAllowFrom(slack) {
  if (!Array.isArray(slack.allowFrom)) {
    return [];
  }

  const values = [];
  for (const entry of slack.allowFrom) {
    if (typeof entry !== "string") {
      continue;
    }

    const trimmed = entry.trim();
    if (trimmed) {
      values.push(trimmed);
    }
  }
  return values;
}

function mergeAllowFrom(existingSlack) {
  const existing = readExistingAllowFrom(existingSlack);
  const configured = readCsv("HYPER_SLACK_ALLOW_FROM");
  return Array.from(new Set([...existing, ...configured]));
}

function readGroupPolicy() {
  const policy = (env.HYPER_SLACK_GROUP_POLICY || "").trim();
  if (!policy) {
    return undefined;
  }

  if (policy !== "open" && policy !== "allowlist" && policy !== "disabled") {
    throw new Error("HYPER_SLACK_GROUP_POLICY must be open, allowlist, or disabled");
  }
  return policy;
}

function isHostedSlackRelayConfig(slack) {
  if (!slack || slack.mode !== "relay") {
    return false;
  }

  const relay = asObject(slack.relay);
  if (!relay) {
    return false;
  }

  return envSecretId(relay.authToken) === HOSTED_RELAY_AUTH_TOKEN_ENV;
}

function buildHostedSlackConfig(existingSlack) {
  const relayUrl = (env.HYPER_SLACK_RELAY_URL || "").trim();
  const gatewayId = (env.HYPER_SLACK_GATEWAY_ID || "").trim();

  if (!relayUrl) {
    throw new Error("HYPER_SLACK_RELAY_URL is required when HYPER_SLACK_APP_ENABLED is true");
  }
  if (!gatewayId) {
    throw new Error("HYPER_SLACK_GATEWAY_ID is required when HYPER_SLACK_APP_ENABLED is true");
  }

  const replyModes = { direct: "off" };
  const existingReplyModes = asObject(existingSlack.replyToModeByChatType);
  if (existingReplyModes) {
    Object.assign(replyModes, existingReplyModes);
  }

  const slack = {
    enabled: true,
    mode: "relay",
    replyToMode: "all",
    replyToModeByChatType: replyModes,
    botToken: { source: "env", provider: "default", id: "SLACK_BOT_TOKEN" },
    relay: {
      url: relayUrl,
      authToken: { source: "env", provider: "default", id: HOSTED_RELAY_AUTH_TOKEN_ENV },
      gatewayId,
    },
  };

  const allowFrom = mergeAllowFrom(existingSlack);
  if (allowFrom.length > 0) {
    slack.dmPolicy = "allowlist";
    slack.allowFrom = allowFrom;
  }

  const groupPolicy = readGroupPolicy();
  if (groupPolicy) {
    slack.groupPolicy = groupPolicy;
  }

  const allowedChannels = readJsonObject("HYPER_SLACK_CHANNELS_JSON");
  if (allowedChannels) {
    slack.channels = allowedChannels;
  }

  return slack;
}

function enableHostedSlackRelay() {
  const channels = ensureObject(config, "channels");
  const messages = ensureObject(config, "messages");
  const plugins = ensureObject(config, "plugins");
  const entries = ensureObject(plugins, "entries");
  const slackEntry = ensureObject(entries, "slack");
  const existingSlack = asObject(channels.slack) || {};
  const statusReactions = asObject(messages.statusReactions) || {};

  channels.slack = buildHostedSlackConfig(existingSlack);
  messages.statusReactions = { ...statusReactions, enabled: true };
  slackEntry.enabled = true;
}

function removeHostedSlackRelay() {
  const channels = asObject(config.channels);
  if (!channels) {
    return;
  }

  const slack = asObject(channels.slack);
  if (!isHostedSlackRelayConfig(slack)) {
    return;
  }

  delete channels.slack;
}

const hostedSlackEnabled = parseBoolean("HYPER_SLACK_APP_ENABLED");
if (hostedSlackEnabled === true) {
  enableHostedSlackRelay();
}
if (hostedSlackEnabled === false) {
  removeHostedSlackRelay();
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
