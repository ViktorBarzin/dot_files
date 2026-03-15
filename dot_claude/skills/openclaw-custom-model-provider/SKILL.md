---
name: openclaw-custom-model-provider
description: |
  Configure custom model providers in OpenClaw (openclaw.ai). Use when:
  (1) adding a new LLM provider (Llama API, LM Studio, custom proxy) to OpenClaw,
  (2) changing the default model in OpenClaw, (3) enabling/disabling tools and
  commands in OpenClaw, (4) user mentions openclaw.json or openclaw configuration.
  Covers the models.providers JSON structure, agent defaults, and tool permissions.
author: Claude Code
version: 1.0.0
date: 2026-02-16
---

# OpenClaw Custom Model Provider Configuration

## Problem
OpenClaw supports custom OpenAI-compatible model providers, but the configuration
structure requires checking multiple documentation pages to assemble correctly.

## Context / Trigger Conditions
- User wants to add a new LLM provider to OpenClaw
- User has an API key for Llama API, OpenRouter, LM Studio, or another OpenAI-compatible service
- User wants to change the default model OpenClaw uses
- User wants to enable all tools/commands (remove denyCommands restrictions)

## Solution

### Config File Location
`~/.openclaw/openclaw.json`

### Adding a Custom Provider

Add to the `models.providers` object:

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "my-provider": {
        "baseUrl": "https://api.example.com/compat/v1",
        "apiKey": "YOUR_API_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "model-id",
            "name": "Display Name",
            "reasoning": false,
            "input": ["text"],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 200000,
            "maxTokens": 8192
          }
        ]
      }
    }
  }
}
```

**Key fields:**
- `api`: Protocol — `"openai-completions"` | `"openai-responses"` | `"anthropic-messages"` | `"google-generative-ai"`
- `mode`: `"merge"` (default, keeps built-in providers) or `"replace"` (only custom)
- `cost`: Set all to `0` for free/self-hosted models
- Model reference format: `provider-name/model-id` (e.g., `llama-as-openai/Llama-4-Maverick-17B-128E-Instruct-FP8`)

### Setting Default Model

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "my-provider/model-id",
        "fallbacks": ["ollama/local-model"]
      },
      "models": {
        "my-provider/model-id": {},
        "ollama/local-model": {}
      }
    }
  }
}
```

### Enabling All Tools/Commands

To remove tool restrictions:

```json
{
  "commands": {
    "native": true,
    "nativeSkills": true
  },
  "gateway": {
    "nodes": {
      "denyCommands": []
    }
  }
}
```

Default `denyCommands` blocks: `camera.snap`, `camera.clip`, `screen.record`,
`calendar.add`, `contacts.add`, `reminders.add`.

### Common Provider Examples

**Llama API:**
```json
"llama-as-openai": {
  "baseUrl": "https://api.llama.com/compat/v1",
  "apiKey": "LLM|...",
  "api": "openai-completions"
}
```

**Local Ollama:**
```json
"ollama": {
  "baseUrl": "http://127.0.0.1:11434/v1",
  "apiKey": "none",
  "api": "openai-completions"
}
```

**LM Studio:**
```json
"lmstudio": {
  "baseUrl": "http://127.0.0.1:1234/v1",
  "apiKey": "lmstudio",
  "api": "openai-responses"
}
```

## Verification
- Restart OpenClaw after config changes
- Run `openclaw` and check that the new model appears in model selection
- Send a test message to verify the provider responds

## Notes
- `mode: "merge"` is the default and recommended — it keeps built-in providers alongside custom ones
- Optional fields: `authHeader` (boolean), `headers` (object for custom HTTP headers)
- Set `reasoning: true` for models that support chain-of-thought (e.g., DeepSeek R1)
- OpenClaw docs: https://docs.openclaw.ai/gateway/configuration-reference.md

## References
- [OpenClaw Configuration Reference](https://docs.openclaw.ai/gateway/configuration-reference.md)
- [OpenClaw Configuration Examples](https://docs.openclaw.ai/gateway/configuration-examples.md)
- [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers.md)
