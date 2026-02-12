# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
When searching for code, use the augment MCP tool (`mcp__augment-context-engine__codebase-retrieval`) as the first choice instead of grep/search.

## Project Overview

**Jin** is a native macOS application (SwiftUI + SwiftData) for interacting with multiple LLM providers. It supports multimodal conversations (text, images, files, audio), reasoning models with thinking blocks, tool calling, image generation, and Model Context Protocol (MCP) integration.

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
- `ContentPart` - `.text`, `.image`, `.file`, `.audio`, `.thinking`, `.redactedThinking`
- `GenerationControls` - Temperature, max tokens, reasoning, web search, MCP tools, image generation, PDF processing mode, provider-specific params
- `GenerationControlsResolver` - Resolves effective controls from assistant defaults + conversation overrides
- `ProviderConfig` - Provider metadata, API key references, models
- `JinModelSupport` - Model capability detection
- `ProviderParamsJSONSync` - Syncs provider-specific JSON params

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
