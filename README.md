# Jin

A native macOS app for chatting with 16 LLM provider types from one workspace.
Jin is intentionally conversation-first: fast, focused, and minimal, without trying to be an all-in-one productivity suite.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
![License: PolyForm Noncommercial](https://img.shields.io/badge/License-PolyForm%20NC%201.0-blue)

## Why Jin

- **Conversation-first** - Built around high-quality chat flow, not workspace clutter
- **Focused controls** - Keep model, reasoning, tool, and media controls close to the conversation
- **Official API parity mindset** - Expose provider parameters as completely as practical instead of hiding them behind generic presets
- **Native performance** - SwiftUI + macOS app behavior, no Electron overhead

## Features

- **Multi-provider chat** - OpenAI, Codex App Server (Beta), OpenAI Compatible, OpenRouter, Anthropic, Perplexity, Groq, Cohere, Mistral, DeepInfra, xAI, DeepSeek, Fireworks, Cerebras, Gemini (AI Studio), and Vertex AI
- **Multimodal conversations** - Send text, images, files, and generated media in one thread
- **Reasoning model UX** - Collapsible thinking blocks for supported models
- **Provider-native web search controls** - Search settings plus in-chat search activity timeline
- **Context cache controls** - Unified caching controls across providers that support prompt caching
- **Tool calling (MCP)** - Connect external tools and data via the Model Context Protocol
- **Image generation** - Gemini, Vertex AI, and xAI image models
- **Video generation** - Gemini/Vertex Veo and xAI video models
- **PDF processing** - Mistral OCR, DeepSeek OCR (DeepInfra), or local PDFKit extraction
- **Voice plugins** - Speech-to-Text (OpenAI, Groq, Mistral) and Text-to-Speech (ElevenLabs, OpenAI, Groq)
- **Assistants** - Named assistants with custom system instructions and model defaults
- **Native macOS app** - SwiftUI app with keyboard shortcuts, drag-and-drop, and proper windowing

## Screenshots

Screenshot placeholders are intentionally kept in this branch. UI screenshots are not committed yet.

Planned screenshot paths:

- `docs/screenshots/hero.png`
- `docs/screenshots/chat.png`
- `docs/screenshots/settings.png`
- `docs/screenshots/mcp-tools.png`
- `docs/screenshots/thinking.png`

## Supported Providers

Jin currently supports 16 provider types (source: `Sources/Domain/ProviderTypes.swift`):

OpenAI, Codex App Server (Beta), OpenAI Compatible, OpenRouter, Anthropic, Perplexity, Groq, Cohere, Mistral, DeepInfra, xAI, DeepSeek, Fireworks, Cerebras, Gemini (AI Studio), Vertex AI.

### Built-in providers on first launch

Jin pre-creates these providers (source: `Sources/Domain/DefaultProviderSeeds.swift`):

OpenAI, Codex App Server (Beta), Groq, OpenRouter, Anthropic, Cohere, Mistral, Perplexity, DeepInfra, xAI, DeepSeek, Fireworks, Gemini (AI Studio), Vertex AI.

`OpenAI Compatible` and `Cerebras` are supported and can be added manually in **Settings > Add Provider**.

### Starter model IDs seeded at first launch

These are the starter model IDs seeded in `Sources/Domain/DefaultProviderSeeds.swift`:

| Provider | Seeded model IDs |
|----------|------------------|
| OpenAI | `gpt-5.2`, `gpt-5.2-2025-12-11`, `gpt-4o` |
| Codex App Server (Beta) | `gpt-5.1-codex` |
| OpenAI Compatible | _(none seeded)_ |
| OpenRouter | _(none seeded)_ |
| Anthropic | `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-opus-4-5-20251101`, `claude-sonnet-4-5-20250929`, `claude-haiku-4-5-20251001` |
| Perplexity | `sonar`, `sonar-pro`, `sonar-reasoning-pro`, `sonar-deep-research` |
| Groq | _(none seeded)_ |
| Cohere | _(none seeded)_ |
| Mistral | _(none seeded)_ |
| DeepInfra | _(none seeded)_ |
| xAI | `grok-4-1-fast`, `grok-4-1`, `grok-imagine-image`, `grok-2-image-1212`, `grok-imagine-video` |
| DeepSeek | `deepseek-chat`, `deepseek-reasoner`, `deepseek-v3.2-exp` |
| Fireworks | `fireworks/glm-5`, `fireworks/minimax-m2p5`, `fireworks/kimi-k2p5`, `fireworks/glm-4p7` |
| Cerebras | _(none seeded)_ |
| Gemini (AI Studio) | `gemini-3-pro-preview`, `gemini-3.1-pro-preview`, `gemini-3-pro-image-preview`, `gemini-3-flash-preview`, `gemini-2.5-flash-image` |
| Vertex AI | `gemini-3-pro-preview`, `gemini-3.1-pro-preview`, `gemini-3-pro-image-preview`, `gemini-3-flash-preview`, `gemini-2.5-pro`, `gemini-2.5-flash-image` |

### How model refresh works

- `Fetch Models` in provider settings calls `adapter.fetchAvailableModels()` for the selected provider.
- API/model-list fetched in adapters: OpenAI, OpenAI Compatible (including Groq, Mistral, DeepInfra), OpenRouter, Anthropic, Cohere, xAI, DeepSeek, Fireworks, Cerebras, Gemini (AI Studio), and Codex App Server (Beta).
- Vertex AI does not call a model-list API in this codebase. It returns a curated static list from `Sources/Adapters/VertexAIAdapter.swift` (`knownModels`).
- Perplexity does not call a model-list API in this adapter. It uses saved provider models, with fallback models: `sonar`, `sonar-pro`, `sonar-reasoning-pro`, `sonar-deep-research`.
- Codex App Server model refresh uses `model/list` over JSON-RPC and supports pagination; if the server returns no models, Jin falls back to `gpt-5.1-codex`.
- Jin refreshes provider models on launch automatically (max once every 24 hours per provider) in `Sources/UI/JinApp.swift`.

### How model capabilities are assigned

- Capabilities (`streaming`, `toolCalling`, `vision`, `audio`, `reasoning`, `promptCaching`, `nativePDF`, `imageGeneration`, `videoGeneration`) are stored in `ModelInfo.capabilities`.
- For fetched model lists, each adapter maps provider data to `ModelInfo` using provider-specific rules.
- Manual model entries use provider-specific ID heuristics in `Sources/UI/AddModelSheet.swift`.

## `✦` Full-Support Badge Rules

`✦` means "Jin full support" in the model list UI.
It highlights models with first-class UX support and curated defaults.
No `✦` does not always mean "unsupported" - it usually means "less opinionated/default-tuned in Jin."

`OpenAI Compatible`, `Groq`, `Cohere`, `Mistral`, and `DeepInfra` are intentionally not auto-badged to avoid over-promising on generic or aggregated routing.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+ (for building from source)

## Installation

### Download

Download the latest `.dmg` from the [Releases](../../releases) page.

### If macOS blocks the app

If macOS shows a warning like "is damaged and can't be opened", Gatekeeper is blocking an unsigned or unnotarized build.

1. Open the DMG and drag `Jin.app` to `/Applications`.
2. Try opening `Jin.app` once so macOS records the block event.
3. Open **System Settings > Privacy & Security**.
4. In the **Security** section, click **Open Anyway** for Jin, then confirm **Open**.

Only do this for builds from a source you trust.

### Build from source

```bash
git clone <repo-url>
cd Jin
swift build
open Package.swift
```

## Getting Started

1. Launch Jin.
2. Open **Settings** and add a provider.
3. Start a new conversation and pick a model.
4. Optional: configure MCP servers under **Settings > MCP Servers** for tool calling.

### Codex App Server (Beta) quick setup

1. Start the local server:
   ```bash
   codex app-server --listen ws://127.0.0.1:4500
   ```
2. In Jin, go to **Settings > Add Provider** and choose **Codex App Server (Beta)**.
3. Configure one auth mode in provider settings: API key, ChatGPT account login, or local Codex auth file.
4. Use **Fetch Models** to pull available Codex models from the running app-server.

Current beta limitation: this provider is designed for server-side built-in tools; client callback-style tool requests are rejected.

## Building & Testing

```bash
swift build                        # Debug build
swift build -c release             # Release build
bash Packaging/package.sh          # Build universal .app bundle (Apple Silicon + Intel)
bash Packaging/package.sh dmg      # Build .dmg installer
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

- All providers implement `LLMProviderAdapter`
- Streaming is `AsyncThrowingStream<StreamEvent, Error>`
- Swift Concurrency throughout (`actor`, `async/await`, `@MainActor`)
- SwiftData for persistence
- Minimal external dependencies: [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)

## Plugins

| Plugin | Services | Setup |
|--------|----------|-------|
| PDF OCR | Mistral OCR, DeepSeek OCR (DeepInfra), local PDFKit extraction | Settings > Plugins |
| Text-to-Speech | ElevenLabs, OpenAI, Groq | Settings > Plugins |
| Speech-to-Text | OpenAI, Groq, Mistral | Settings > Plugins |
| Chat Naming | Automatic conversation naming with a selected model | Settings > Plugins |
| Cloudflare R2 Upload | Upload local videos to R2 and send public URLs | Settings > Plugins |

## MCP (Model Context Protocol)

Jin supports connecting to MCP servers for tool calling. Configure servers under **Settings > MCP Servers**. Both long-running (persistent) and ephemeral servers are supported, with per-server tool enable/disable.

## Contributing

Contributions are welcome. Please note that all contributions fall under the same [PolyForm Noncommercial License](LICENSE).

## License

This project is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE). You are free to use, modify, and distribute this software for noncommercial purposes. See the [full license text](https://polyformproject.org/licenses/noncommercial/1.0.0/) for details.

## Acknowledgments

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) - Model Context Protocol client library
- [Lobe Icons](https://github.com/lobehub/lobe-icons) - Provider icon assets
