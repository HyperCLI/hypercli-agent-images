{
  "models": {
    "mode": "merge",
    "providers": {
      "hypercli": {
        "baseUrl": "${HYPER_AGENTS_API_BASE}",
        "apiKey": "${HYPER_AGENTS_API_KEY}",
        "api": "anthropic-messages",
        "authHeader": true,
        "models": [
          {
            "id": "kimi-k2.6-anthropic",
            "name": "Kimi K2.6",
            "reasoning": true,
            "input": ["text", "image"],
            "contextWindow": 262144,
            "maxTokens": 262144
          },
          {
            "id": "glm-5-anthropic",
            "name": "GLM-5",
            "reasoning": true,
            "input": ["text"],
            "contextWindow": 202752,
            "maxTokens": 131072
          }
        ]
      }
    }
  },
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:18789",
        "http://127.0.0.1:18789",
        "${OPENCLAW_CONTROL_UI_ALLOWED_ORIGIN}"
      ]
    },
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    }
  },
  "browser": {
    "enabled": true,
    "defaultProfile": "openclaw",
    "headless": false,
    "noSandbox": true,
    "executablePath": "/usr/bin/google-chrome-stable",
    "profiles": {
      "openclaw": {
        "cdpPort": 18800,
        "color": "#FF4500",
        "headless": false,
        "executablePath": "/usr/bin/google-chrome-stable"
      }
    }
  },
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "model": {
        "primary": "hypercli/kimi-k2.6-anthropic"
      },
      "models": {
        "hypercli/kimi-k2.6-anthropic": {
          "alias": "kimi"
        },
        "hypercli/glm-5-anthropic": {
          "alias": "glm"
        }
      },
      "memorySearch": {
        "enabled": true,
        "provider": "openai",
        "model": "qwen3-embedding-4b",
        "remote": {
          "baseUrl": "${HYPER_AGENTS_API_BASE}/v1",
          "apiKey": "${HYPER_AGENTS_API_KEY}"
        },
        "sync": {
          "onSessionStart": false,
          "onSearch": false,
          "watch": false,
          "watchDebounceMs": 30000,
          "intervalMinutes": 0
        }
      }
    },
    "list": [
      {
        "id": "default",
        "name": "OpenClaw Assistant",
        "workspace": "~/.openclaw/workspace"
      }
    ]
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "cron": {
    "enabled": false
  },
  "plugins": {
    "entries": {
      "brave": {
        "enabled": true,
        "config": {
          "webSearch": {
            "baseUrl": "${HYPER_AGENTS_WEB_SEARCH_BASE}",
            "apiKey": "${HYPER_AGENTS_API_KEY}"
          }
        }
      },
      "browser": {
        "enabled": true
      }
    }
  },
  "tools": {
    "alsoAllow": ["browser"],
    "web": {
      "search": {
        "enabled": true,
        "provider": "brave"
      }
    }
  }
}
