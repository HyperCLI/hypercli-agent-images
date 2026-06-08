#!/usr/bin/env node
import fs from "node:fs";

const configPath = process.argv[2];
if (!configPath) {
  console.error("usage: configure-openclaw-web-search.mjs <config-path>");
  process.exit(2);
}

const raw = fs.readFileSync(configPath, "utf8");
const config = JSON.parse(raw);

function ensureRecord(parent, key) {
  if (!parent[key] || typeof parent[key] !== "object" || Array.isArray(parent[key])) {
    parent[key] = {};
  }
  return parent[key];
}

const tools = ensureRecord(config, "tools");
const web = ensureRecord(tools, "web");
const search = ensureRecord(web, "search");
search.enabled = true;
search.provider = "brave";

const plugins = ensureRecord(config, "plugins");
const entries = ensureRecord(plugins, "entries");
const brave = ensureRecord(entries, "brave");
brave.enabled = true;

const braveConfig = ensureRecord(brave, "config");
const webSearch = ensureRecord(braveConfig, "webSearch");
webSearch.baseUrl = process.env.HYPER_AGENTS_WEB_SEARCH_BASE || "${HYPER_AGENTS_WEB_SEARCH_BASE}";
webSearch.apiKey = process.env.HYPER_AGENTS_API_KEY || "${HYPER_AGENTS_API_KEY}";

const next = `${JSON.stringify(config, null, 2)}\n`;
if (next !== raw) {
  fs.writeFileSync(configPath, next);
  console.log("[openclaw] web search config updated");
}
