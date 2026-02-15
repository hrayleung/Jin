# Jin

A native macOS app for chatting with 15+ LLM providers.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
![License: PolyForm Noncommercial](https://img.shields.io/badge/License-PolyForm%20NC%201.0-blue)

<!-- TODO: Replace with actual screenshot -->
<p align="center">
  <img src="docs/screenshots/hero.png" alt="Jin main chat interface" width="800">
</p>

## Features

- **Multi-Provider Support** -- Connect to 15+ LLM providers through a single app: OpenAI, Anthropic, Google Gemini, Vertex AI, Perplexity, Groq, OpenRouter, xAI (Grok), DeepSeek, Mistral, Cohere, DeepInfra, Cerebras, Fireworks, and any OpenAI-compatible API
- **Multimodal Conversations** -- Send text, images, and files in a single conversation
- **Reasoning Models** -- Collapsible thinking blocks for supported reasoning models
- **Tool Calling (MCP)** -- Connect AI to external tools and data sources via the Model Context Protocol
- **Image Generation** -- Generate images with Gemini and xAI (Grok) models
- **PDF Processing** -- Extract text from PDFs via Mistral OCR, DeepInfra, or local PDFKit
- **Voice Plugins** -- Speech-to-Text (OpenAI, Groq) and Text-to-Speech (ElevenLabs, OpenAI, Groq)
- **Assistants** -- Create named assistants with custom system instructions, model preferences, and temperature settings
- **Native macOS** -- Built with SwiftUI. Keyboard shortcuts, drag-and-drop, proper window management. No Electron.

## Screenshots

<!-- TODO: Replace with actual screenshots -->
<p align="center">
  <img src="docs/screenshots/chat.png" alt="Chat conversation view" width="400">&nbsp;&nbsp;
  <img src="docs/screenshots/settings.png" alt="Settings and provider configuration" width="400">
</p>
<p align="center">
  <img src="docs/screenshots/mcp-tools.png" alt="MCP tool calling in action" width="400">&nbsp;&nbsp;
  <img src="docs/screenshots/thinking.png" alt="Reasoning model with thinking blocks" width="400">
</p>

## Supported Providers

OpenAI, OpenAI Compatible, OpenRouter, Anthropic, Perplexity, Groq, Cohere, Mistral, DeepInfra, xAI, DeepSeek, Fireworks, Cerebras, Gemini (AI Studio), Vertex AI.

### How Jin gets model IDs

- Jin pulls model IDs from provider APIs for OpenAI, OpenAI Compatible (including Groq/Mistral/DeepInfra endpoints), OpenRouter, Anthropic, Cohere, xAI, DeepSeek, Fireworks, Cerebras, Gemini (AI Studio), and Vertex AI.
- Perplexity currently uses a built-in fallback list when no custom list is configured: `sonar`, `sonar-pro`, `sonar-reasoning-pro`, `sonar-deep-research`.
- On first launch, Jin seeds starter model IDs so you can chat immediately. Use provider model refresh in Settings to sync with current provider lists.

## `✦` Full-Support Badge Rules

`✦` means "Jin full support" in the model list UI. The matching rules come directly from `Sources/Domain/JinModelSupport.swift`.

| Provider | `✦` model matching rule |
|----------|--------------------------|
| OpenAI | Prefix: `gpt-5`, `o3`, `o4`, `gpt-4o` |
| Anthropic | Contains: `claude-opus-4`, `claude-sonnet-4`, `claude-haiku-4` |
| Perplexity | Contains: `sonar-pro`, `sonar-reasoning`, `sonar-deep-research` |
| xAI | Contains: `grok-4`, `grok-5`, `grok-6`, `imagine-image`, `grok-2-image` |
| DeepSeek | Exact: `deepseek-chat`, `deepseek-reasoner`; or contains `deepseek-v3.2-exp` |
| Fireworks | Exact: `fireworks/kimi-k2p5`, `accounts/fireworks/models/kimi-k2p5`, `fireworks/glm-4p7`, `accounts/fireworks/models/glm-4p7`, `fireworks/glm-5`, `accounts/fireworks/models/glm-5`, `fireworks/minimax-m2p5`, `accounts/fireworks/models/minimax-m2p5` |
| Cerebras | Exact: `zai-glm-4.7` |
| Gemini (AI Studio) | Contains: `gemini-3`, `gemini-2.5-flash-image` |
| Vertex AI | Contains: `gemini-3`, `gemini-2.5` |

For `OpenAI Compatible`, `OpenRouter`, `Groq`, `Cohere`, `Mistral`, and `DeepInfra`, `✦` is intentionally not auto-assigned in code to avoid over-promising on generic/aggregated routing.

## Latest Provider Models (Official Docs, verified 2026-02-15)

These are the latest model IDs/families published by provider docs at verification time. They are not the same as Jin `✦` rules.

| Provider | Latest official model IDs/families (examples) |
|----------|-----------------------------------------------|
| OpenAI | `gpt-5.2`, `gpt-5.2-2025-08-07`, `gpt-5`, `gpt-5-mini` |
| Anthropic | `claude-opus-4-6`, `claude-opus-4-6-20260106`, `claude-opus-4-1`, `claude-sonnet-4` |
| Perplexity | `sonar`, `sonar-pro`, `sonar-reasoning-pro`, `sonar-deep-research` |
| xAI | `grok-4-1`, `grok-4-1-fast-reasoning`, `grok-4-fast-reasoning`, `grok-4-fast-non-reasoning` |
| DeepSeek | `deepseek-chat`, `deepseek-reasoner`, `deepseek-v3.2-exp` |
| Fireworks | `fireworks/glm-5`, `fireworks/kimi-k2p5`, `fireworks/minimax-m2p5` |
| Cerebras | `zai-glm-4.7`, `gpt-oss-120b`, `qwen-3-32b`, `qwen-3-235b-2507`, `llama3.1-8b` |
| Gemini (AI Studio) | `gemini-3.0-pro`, `gemini-3.0-flash`, `gemini-2.5-flash-image` |
| Vertex AI | Gemini 3.0 Pro/Flash and Gemini 2.5 family (model IDs exposed under `publishers/google/models/*`) |

Reference links:

- OpenAI: https://platform.openai.com/docs/models/latest-model and https://platform.openai.com/docs/models/gpt-5.2
- Anthropic: https://docs.anthropic.com/en/docs/about-claude/models/overview and https://www.anthropic.com/news/claude-opus-4-6
- Perplexity: https://docs.perplexity.ai/guides/model-cards and https://docs.perplexity.ai/changelog/changelog
- xAI: https://docs.x.ai/docs/changelog and https://docs.x.ai/docs/tutorial
- DeepSeek: https://api-docs.deepseek.com/quick_start/pricing and https://api-docs.deepseek.com/news/news250926
- Fireworks: https://fireworks.ai/models/fireworks/glm-5 and https://fireworks.ai/models/fireworks/kimi-k2p5
- Cerebras: https://inference-docs.cerebras.ai/api-reference/models/public-models and https://inference-docs.cerebras.ai/models/zai-glm-47
- Gemini (AI Studio): https://ai.google.dev/gemini-api/docs/models/gemini and https://ai.google.dev/gemini-api/docs/models/experimental-models
- Vertex AI: https://cloud.google.com/vertex-ai/generative-ai/docs/learn/models

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+ (for building from source)

## Installation

### Download

Download the latest `.dmg` from the [Releases](../../releases) page.

### If macOS Blocks the App

If macOS shows a warning like "is damaged and can't be opened", Gatekeeper is blocking an unsigned or unnotarized build.

1. Open the DMG and drag `Jin.app` to `/Applications`.
2. In Finder, Control-click `Jin.app` and choose **Open**.
3. Click **Open** again in the confirmation dialog.
4. If it is still blocked, remove quarantine attributes:

```bash
xattr -dr com.apple.quarantine /Applications/Jin.app
```

If the DMG itself is blocked, run:

```bash
xattr -dr com.apple.quarantine ~/Downloads/Jin.dmg
```

Only run these commands for builds from a source you trust.

### Build from Source

```bash
git clone <repo-url>
cd jin
swift build
open Package.swift   # or open in Xcode
```

## Getting Started

1. Launch Jin
2. Open **Settings** and add a provider with your API key
3. Start a new conversation and pick a model
4. (Optional) Configure MCP servers under **Settings > MCP** for tool calling

## Building & Testing

```bash
swift build                        # Debug build
swift build -c release             # Release build
./Packaging/package.sh             # Build .app bundle
./Packaging/package.sh dmg         # Build .dmg installer
swift test                         # Run all tests
swift test --filter FooTests       # Run a single test suite
```

## Architecture

```
Sources/
  UI/           SwiftUI views and app entry point
  Domain/       Core models (Message, ContentPart, GenerationControls)
  Adapters/     LLM provider implementations (LLMProviderAdapter protocol)
  Networking/   HTTP, SSE streaming, OCR/TTS/STT clients
  Persistence/  SwiftData entities and storage
  MCP/          Model Context Protocol client (MCPHub, MCPClient)
  Resources/    HTML templates, provider icons
```

Key design choices:

- All providers implement the `LLMProviderAdapter` protocol
- Streaming via `AsyncThrowingStream<StreamEvent, Error>`
- Swift Concurrency throughout (actors, async/await, `@MainActor`)
- SwiftData for persistence
- Minimal external dependencies -- only the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)

## Plugins

| Plugin | Services | Setup |
|--------|----------|-------|
| PDF OCR | Mistral, DeepInfra, Local (PDFKit) | Settings > Plugins |
| Text-to-Speech | ElevenLabs, OpenAI, Groq | Settings > Plugins |
| Speech-to-Text | OpenAI, Groq | Settings > Plugins |

## MCP (Model Context Protocol)

Jin supports connecting to MCP servers for tool calling. Configure servers under **Settings > MCP Servers**. Both long-running (persistent) and ephemeral servers are supported, with per-server tool enable/disable.

## Contributing

Contributions are welcome. Please note that all contributions fall under the same [PolyForm Noncommercial License](LICENSE).

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE). You are free to use, modify, and distribute this software for noncommercial purposes. See the [full license text](https://polyformproject.org/licenses/noncommercial/1.0.0/) for details.

## Acknowledgments

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) -- Model Context Protocol client library
- [Lobe Icons](https://github.com/lobehub/lobe-icons) -- Provider icon assets
