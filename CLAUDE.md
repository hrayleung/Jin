# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
When searching for code, use the augment MCP tool (`mcp__augment-context-engine__codebase-retrieval`) as the first choice instead of grep/search.

## Critical Rule: Verify External APIs Before Writing Code

**NEVER guess API request/response formats.** Before writing any code that calls an external API (LLM providers, video generation, etc.):

1. **Read the official API documentation first** — use WebFetch/WebSearch to look up the actual endpoint, parameters, types, and model-specific constraints.
2. **Cross-verify** — don't blindly trust a single doc page or plan. If a plan says "send `numberOfVideos`", verify that parameter actually exists in the API.
3. **Check per-model differences** — different model versions (e.g., Veo 2 vs Veo 3 vs Veo 3.1) often support different parameter sets. Map out the compatibility matrix before writing code.
4. **Check per-provider differences** — the same model family may have different API shapes across providers (e.g., Gemini API vs Vertex AI use different parameter names and types for the same Veo models).
5. **Use common sense on types** — if a parameter is called `durationSeconds`, it's a number, not a string. Don't blindly copy formats from scraped docs without thinking.
6. **Never make the user your test runner** — get the API details right the first time instead of shipping untested guesses that fail one by one.

## Project Overview

**Jin** is a native macOS application (SwiftUI + SwiftData) for interacting with multiple LLM providers. It supports multimodal conversations (text, images, files, audio, video), reasoning models with thinking blocks, tool calling, image/video generation, cross-provider context caching, and Model Context Protocol (MCP) integration.

## Build & Run Commands

```bash
swift build                    # Build the project
swift test                     # Run all tests
swift test --filter FooTests   # Run a single test suite
swift run Jin                  # Run from CLI (not typical for GUI apps)
open Package.swift             # Open in Xcode for UI development
./Packaging/package.sh         # Build release .app bundle
./Packaging/package.sh dmg     # Build release .dmg installer
```

**Requirements**: macOS 14 (Sonoma)+, Swift 5.9+

## Workflow

After completing each feature or fix, run `./Packaging/package.sh` to build the release .app bundle.

## Architecture

Jin follows a layered architecture in `Sources/`:

```
UI/           → SwiftUI views, app entry (JinApp.swift), streaming state, preferences
Domain/       → Core models (Message, ContentPart, GenerationControls, ToolDefinition)
Adapters/     → LLM provider implementations (LLMProviderAdapter protocol)
Networking/   → HTTP, SSE streaming, PDF/OCR/audio clients
Persistence/  → SwiftData entities, attachment storage, favorite models
MCP/          → Model Context Protocol client (MCPHub, MCPClient)
Resources/    → HTML templates, provider icons
```

### Adapter Layer

All providers implement the `LLMProviderAdapter` protocol (`sendMessage`, `validateAPIKey`, `fetchAvailableModels`, `translateTools`). Adapters return `AsyncThrowingStream<StreamEvent, Error>` for streaming.

**Provider types** (see `ProviderType` enum in `GenerationControls.swift`): openai, openaiCompatible, openrouter, anthropic, perplexity, groq, cohere, mistral, deepinfra, xai, deepseek, fireworks, cerebras, gemini, vertexai.

**Shared core**: `OpenAIChatCompletionsCore.swift` provides shared request/response decoding for all OpenAI-compatible adapters (OpenAI, DeepSeek, Cerebras, Fireworks, Groq, Perplexity, OpenRouter, OpenAICompatible). `OpenAICompatibleAdapter` is the generic base.

**Anthropic-specific**: `AnthropicRequestPreflight.swift` preprocesses requests, `AnthropicToolUseNormalizer.swift` normalizes tool use. `AnthropicModelLimits.swift` tracks model-specific limits.

**Adding a new provider**:
1. Create `Sources/Adapters/NewProviderAdapter.swift` implementing `LLMProviderAdapter`
2. Add case to `ProviderType` enum in `GenerationControls.swift`
3. Add factory case in `ProviderManager.createAdapter(for:)`

### Domain Layer

- `Message` - Contains `role`, `content: [ContentPart]`, `toolCalls`, `toolResults`
- `ContentPart` - `.text`, `.image`, `.file`, `.audio`, `.video`, `.thinking`, `.redactedThinking`
- `VideoContent` - Video data model (mirrors `ImageContent`): `mimeType`, `data`, `url`
- `GenerationControls` - Temperature, max tokens, reasoning, web search, MCP tools, image/video generation, PDF processing mode, context cache controls, provider-specific params
- `ContextCacheControls` - Unified cross-provider cache configuration: mode (off/implicit/explicit), strategy (systemOnly/systemAndTools/prefixWindow), TTL, and provider-specific fields (`cacheKey` for OpenAI, `conversationID` for xAI, `cachedContentName` for Google)
- `XAIImageGenerationControls` / `XAIVideoGenerationControls` - xAI-specific generation params (aspect ratio, duration, resolution)
- `GoogleVideoGenerationControls` - Google Veo-specific video generation params (duration, aspect ratio, resolution, negative prompt, audio, person generation, seed)
- `GenerationControlsResolver` - Resolves effective controls from assistant defaults + conversation overrides
- `ProviderConfig` - Provider metadata, API key references, models
- `JinModelSupport` - Model capability detection (`.videoGeneration`, `.imageGeneration`, `.promptCaching`, `.reasoning`, etc.)
- `ProviderParamsJSONSync` - Syncs provider-specific JSON params bidirectionally between typed controls and raw JSON

### Persistence Layer

SwiftData entities in `SwiftDataModels.swift`:
- `AssistantEntity` - Named assistant configurations with system instructions, temperature, truncation settings
- `ConversationEntity` - Conversations with messages and model config
- `MessageEntity` - Persisted messages (use `toDomain()` / `fromDomain()` conversions)
- `ProviderConfigEntity` - Provider configurations with `apiKeyKeychainID`
- `MCPServerConfigEntity` - MCP server configurations (see `MCPServerConfigEntity+Domain.swift` for mapping)
- `AttachmentEntity` - File attachments

**Pattern**: Complex fields are stored as serialized JSON `Data` (e.g., `contentData`, `modelConfigData`).

### Streaming Architecture

1. `ConversationStreamingStore` (main actor) tracks active streaming sessions by conversation ID
2. Adapters return `AsyncThrowingStream<StreamEvent, Error>` with events: `.messageStart`, `.contentDelta`, `.thinkingDelta`, `.toolCallStart/Delta/End`, `.messageEnd`, `.error`
3. Streaming continues in background even when user navigates away

### Video Generation (xAI)

xAI adapter supports async video generation via polling:

1. `sendMessage()` detects video generation models via `isVideoGenerationModel()`
2. POST to `/videos/generations` → returns a request ID
3. Polling loop: GET `/videos/{requestID}` every 3s, max 200 attempts (~10 min timeout)
4. Status resolution from multiple possible JSON response structures
5. HTTP error handling: 404/410 → expired, 500+ → failed, 4xx → failed
6. Video downloaded and saved to `~/Library/Application Support/Jin/Attachments/{UUID}.{ext}`
7. MIME type inferred from Content-Type header → URL extension → default MP4
8. Yielded as `.contentDelta(.video(VideoContent))`

Supports both text-to-video and image-to-video inputs.

### Video Generation (Google Veo)

Both Gemini (AI Studio) and Vertex AI adapters support Veo video generation models (Veo 2, 3, 3.1) via async polling:

1. `sendMessage()` detects Veo models via `GoogleVideoGenerationCore.isVideoGenerationModel()` (checks for `veo-` in model ID)
2. **Gemini**: POST to `{baseURL}/models/{modelID}:predictLongRunning` with API key header
3. **Vertex**: POST to `{baseURL}/projects/{pid}/locations/{loc}/publishers/google/models/{modelID}:predictLongRunning` with Bearer token
4. Request body: `{ "instances": [{ "prompt": "...", "image": {...} }], "parameters": { aspectRatio, resolution, durationSeconds, negativePrompt, generateAudio, personGeneration, seed } }`
5. Response returns `{ "name": "operations/..." }` (LRO operation name)
6. **Gemini polling**: GET `{baseURL}/{operationName}` every 10s, max 60 attempts (~10 min)
7. **Vertex polling**: POST `{baseURL}/.../models/{modelID}:fetchPredictOperation` with `{ "operationName": "..." }` every 10s
8. On `done: true`: extract video from response
9. **Gemini**: video URI in `response.generateVideoResponse.generatedSamples[0].video.uri`, downloaded with API key query param
10. **Vertex**: video as `videos[0].bytesBase64Encoded` (inline) or `videos[0].gcsUri` (GCS URI → authenticated download)
11. Shared utilities in `GoogleVideoGenerationCore.swift`: model detection, prompt/image extraction, video download/save, format resolution
12. Video saved to `~/Library/Application Support/Jin/Attachments/{UUID}.{ext}`
13. Yielded as `.contentDelta(.video(VideoContent))`

Supports text-to-video and image-to-video inputs. Controls configured via `GoogleVideoGenerationControls` in `GenerationControls.swift`.

### Context Caching

Cross-provider prompt caching with automatic strategy selection:

| Provider | Method | Key Mechanism |
|----------|--------|---------------|
| Anthropic | Native cache headers | `cache_control` blocks on content |
| OpenAI | Prompt cache control | `prompt_cache_control`, `cache_key` |
| xAI | Conversation-level cache | `x-grok-conv-id` header + `prompt_cache_key`/`prompt_cache_retention` |
| Gemini/Vertex | Explicit cache resources | `cachedContents/{id}` resource naming |

Configuration via `ContextCacheControls` in `GenerationControls.swift`. Strategies: `systemOnly` (cache system prompt), `systemAndTools` (cache system + tool definitions), `prefixWindow` (cache conversation prefix). TTL options: provider default, 5 min, 1 hour, custom seconds.

### MCP Integration

- `MCPHub` (actor) manages connections and routes tool calls to correct server
- Function names namespaced as `{serverID}__{toolName}` (truncated if >64 chars)
- Tools disabled per-server via `disabledTools` array
- Supports long-running (persistent) vs. ephemeral servers
- Default servers seeded in `JinApp.seedDefaultMCPServersIfNeeded()`

### Tool Execution Flow

1. `MCPHub.toolDefinitions()` aggregates tools from enabled MCP servers
2. Tools passed to adapter's `sendMessage()` via `translateTools()`
3. Provider returns `.toolCallStart/Delta/End` events
4. ChatView executes tools via `MCPHub.executeTool()`
5. Tool results appended as new message with `role: .tool`

## Networking

- `NetworkManager` handles HTTP requests with `sendRequest()` (throws on non-2xx) and `sendRawRequest()` (returns raw data + response for custom status handling, used by video polling)
- SSE streaming via dedicated SSE client
- All API keys stored in macOS Keychain, referenced by keychain IDs

## Plugins

Optional features configured via Settings, each with dedicated keychain IDs:

| Plugin | Clients | Keychain IDs |
|--------|---------|-------------|
| PDF OCR | `MistralOCRClient`, `DeepInfraDeepSeekOCRClient`, `PDFKitTextExtractor` (local) | `plugin_mistral_ocr`, `plugin_deepinfra_deepseek_ocr` |
| TTS | `ElevenLabsTTSClient` + OpenAI/Groq TTS | `plugin_elevenlabs_tts`, `plugin_openai_tts`, `plugin_groq_tts` |
| STT | `OpenAIAudioClient`, `GroqAudioClient` | `plugin_openai_stt`, `plugin_groq_stt` |

## Dependencies

- **MCP Swift SDK** (0.10.0+) - Model Context Protocol client library
- All other functionality uses native macOS/Swift frameworks (no external UI/networking deps)

## Swift Concurrency

- **Actors**: `ProviderManager`, `MCPHub`, `MCPClient`, adapter protocol
- **@MainActor**: `ConversationStreamingStore`, SwiftUI views
- **AsyncThrowingStream** for all streaming responses

## Code Style

- 4-space indentation, no tabs
- One primary type per file, filename matches type name
- Views: `*View`, Entities: `*Entity`, Adapters: `*Adapter`
- Prefer `actor` for shared mutable state, `@MainActor` for UI-bound state

## Testing

- Framework: XCTest, location: `Tests/JinTests/`
- Pattern: `*Tests.swift`, `final class FooTests: XCTestCase`
- Focus: Unit tests for Domain, Networking, Persistence; avoid network-dependent tests
- Run single suite: `swift test --filter FooTests`
- Notable test files: `XAIAdapterMediaTests.swift` (video/image generation), `OpenAIAdapterPromptCachingTests.swift` (cache logic)

## SwiftData Pitfalls

### Persistence in SwiftUI Forms

SwiftData requires explicit `modelContext.save()` in child views using `@Bindable`. Without it, changes silently don't persist:

```swift
// WRONG - changes won't persist
set: { newValue in assistant.name = newValue }

// CORRECT - must inject modelContext and save
@Environment(\.modelContext) private var modelContext
set: { newValue in
    assistant.name = newValue
    assistant.updatedAt = Date()
    try? modelContext.save()
}
```

This applies to ALL bindings in `AssistantInspectorView.swift` (name, icon, description, systemInstruction, temperature, maxOutputTokens, truncateMessages, maxHistoryMessages, replyLanguage).

### TextField Placeholders

```swift
// WRONG - first param is label, not placeholder
TextField("Assistant name", text: binding)

// CORRECT - use prompt parameter
TextField(text: binding, prompt: Text("e.g., Code Assistant")) { EmptyView() }
```

### Testing Checklist for Settings UI

When modifying any SwiftData-backed form:
1. Change value, close and reopen settings, verify it persisted
2. Test edge cases: empty values, very long text, special characters, emoji
3. Verify `updatedAt` timestamp changes
4. Start new chat to confirm defaults applied
