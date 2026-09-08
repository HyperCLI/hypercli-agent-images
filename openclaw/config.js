const fs = require("fs")

const configPath = process.env.CONFIG_PATH
const config = JSON.parse(fs.readFileSync(configPath, "utf8"))
const env = process.env

function parseBoolean(name) {
  const raw = env[name]
  if (raw === undefined || raw === "") return undefined
  switch (raw.trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
    case "enabled":
      return true
    case "0":
    case "false":
    case "no":
    case "off":
    case "disabled":
      return false
    default:
      throw new Error(`${name} must be a boolean-like value`)
  }
}

function parseNonNegativeInteger(name) {
  const raw = env[name]
  if (raw === undefined || raw === "") return undefined
  if (!/^\d+$/.test(raw.trim())) throw new Error(`${name} must be a non-negative integer`)
  return Number.parseInt(raw.trim(), 10)
}

const defaults = (((config.agents ||= {}).defaults ||= {}))
const memorySearch = ((defaults.memorySearch ||= {}))
const sync = ((memorySearch.sync ||= {}))
const workspaceIndexPath = "~/shared"
const extraPaths = Array.isArray(memorySearch.extraPaths) ? memorySearch.extraPaths : []
if (!extraPaths.includes(workspaceIndexPath)) extraPaths.push(workspaceIndexPath)
memorySearch.extraPaths = extraPaths

const enabled = parseBoolean("OPENCLAW_MEMORY_SEARCH_ENABLED")
if (enabled !== undefined) memorySearch.enabled = enabled

const onSessionStart = parseBoolean("OPENCLAW_MEMORY_SEARCH_SYNC_ON_SESSION_START")
if (onSessionStart !== undefined) sync.onSessionStart = onSessionStart

const onSearch = parseBoolean("OPENCLAW_MEMORY_SEARCH_SYNC_ON_SEARCH")
if (onSearch !== undefined) sync.onSearch = onSearch

const watch = parseBoolean("OPENCLAW_MEMORY_SEARCH_SYNC_WATCH")
if (watch !== undefined) sync.watch = watch

const watchDebounceMs = parseNonNegativeInteger("OPENCLAW_MEMORY_SEARCH_SYNC_WATCH_DEBOUNCE_MS")
if (watchDebounceMs !== undefined) sync.watchDebounceMs = watchDebounceMs

const intervalMinutes = parseNonNegativeInteger("OPENCLAW_MEMORY_SEARCH_SYNC_INTERVAL_MINUTES")
if (intervalMinutes !== undefined) sync.intervalMinutes = intervalMinutes

const cronEnabled = parseBoolean("OPENCLAW_CRON_ENABLED")
if (cronEnabled !== undefined) {
  const cron = ((config.cron ||= {}))
  cron.enabled = cronEnabled
}

const desktopEnabled = parseBoolean("HYPER_DESKTOP_ENABLED") === true
if (desktopEnabled === true) {
  const chromePath = env.CHROME_EXECUTABLE_PATH || "/usr/local/bin/hypercli-chrome"
  const browser = ((config.browser ||= {}))
  browser.enabled = true
  browser.headless = false
  browser.noSandbox = true
  browser.executablePath = chromePath
  if (typeof browser.defaultProfile !== "string" || !browser.defaultProfile) browser.defaultProfile = "openclaw"
  const profiles = ((browser.profiles ||= {}))
  const profile = ((profiles[browser.defaultProfile] ||= {}))
  if (profile.cdpPort === undefined) profile.cdpPort = 18800
  if (profile.color === undefined) profile.color = "#FF4500"
  profile.headless = false
  profile.executablePath = chromePath
  const entries = (((config.plugins ||= {}).entries ||= {}))
  const browserEntry = ((entries.browser ||= {}))
  browserEntry.enabled = true
  const tools = ((config.tools ||= {}))
  if (!Array.isArray(tools.alsoAllow)) tools.alsoAllow = []
  if (!tools.alsoAllow.includes("browser")) tools.alsoAllow.push("browser")
} else if (parseBoolean("HYPER_DESKTOP_ENABLED") === false) {
  if (config.browser && typeof config.browser === "object") config.browser.enabled = false
  const entries = config.plugins && config.plugins.entries
  if (entries && entries.browser && typeof entries.browser === "object") entries.browser.enabled = false
  if (config.tools && Array.isArray(config.tools.alsoAllow)) {
    config.tools.alsoAllow = config.tools.alsoAllow.filter((tool) => tool !== "browser")
  }
}

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n")
