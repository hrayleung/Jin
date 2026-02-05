# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
When searching for code, use the augment MCP tool (`mcp__augment-context-engine__codebase-retrieval`) as the first choice instead of grep/search.

## Project Overview

**Jin** is a native macOS application (SwiftUI + SwiftData) for interacting with multiple LLM providers (OpenAI, Anthropic, xAI, Vertex AI, Fireworks, Cerebras). It supports multimodal conversations (text, images, files, audio), advanced reasoning models with thinking blocks, tool calling, and Model Context Protocol (MCP) integration.

## Build & Run Commands

```bash
# Build the project
swift build

# Run from CLI (not common for GUI apps)
swift run Jin

# Run tests
swift test

# Build release and create .app bundle
./Packaging/package.sh

# Build release and create .dmg installer
./Packaging/package.sh dmg

# Open in Xcode for UI development
open Package.swift
```

## Architecture & Code Organization

Jin follows a layered architecture organized by domain responsibility:

### **Sources/UI/** - SwiftUI Views & App Entry

- `JinApp.swift` - App entry point, initializes SwiftData `ModelContainer` with all entity types
- `ChatView.swift` - Main conversation interface
- `ContentView.swift` - Root view with navigation
- `ConversationStreamingStore.swift` - Tracks active streaming sessions across conversations (allows background streaming)
- `SettingsView.swift` - Provider and assistant configuration

**Pattern**: Views follow `*View` naming convention

### **Sources/Domain/** - Core Business Logic

Core data structures and business logic, independent of UI and persistence:

- `Message.swift` - Central message model supporting multimodal content (`ContentPart` enum for text/image/file/audio/thinking)
- `GenerationControls.swift` - Model configuration, provider configs, model capabilities
- `ToolDefinition.swift` - Tool definitions (from MCP or built-in)
- `ChatHistoryTruncator.swift` - Context window management

**Key Types**:

- `Message` - Contains `role`, `content: [ContentPart]`, `toolCalls`, `toolResults`
- `ContentPart` - `.text`, `.image`, `.file`, `.audio`, `.thinking`, `.redactedThinking`
- `GenerationControls` - Temperature, max tokens, reasoning controls, tool controls
- `ProviderConfig` - Provider metadata, API keys (keychain IDs), models

### **Sources/Adapters/** - LLM Provider Integrations

Provider-specific implementations following the `LLMProviderAdapter` protocol:

- `LLMProviderAdapter.swift` - Protocol defining `sendMessage`, `validateAPIKey`, `fetchAvailableModels`, `translateTools`
- `ProviderManager.swift` - Factory actor that creates adapters and resolves credentials from Keychain
- Individual adapters: `OpenAIAdapter`, `AnthropicAdapter`, `XAIAdapter`, `VertexAIAdapter`, `FireworksAdapter`, `CerebrasAdapter`
- `AnthropicRequestPreflight.swift`, `AnthropicToolUseNormalizer.swift` - Anthropic-specific preprocessing

**Pattern**: Adapters translate between Jin's normalized domain models and provider-specific API formats. They return `AsyncThrowingStream<StreamEvent, Error>` for streaming responses.

**Stream Events**: `.messageStart`, `.contentDelta`, `.thinkingDelta`, `.toolCallStart/Delta/End`, `.messageEnd`, `.error`

### **Sources/Persistence/** - Data Storage

SwiftData persistence layer with domain conversion methods:

- `SwiftDataModels.swift` - Defines all `@Model` entities:
  - `AssistantEntity` - Named assistant configurations with system instructions
  - `ConversationEntity` - Conversations with messages and model config
  - `MessageEntity` - Persisted messages (with `toDomain()` conversion)
  - `ProviderConfigEntity` - Provider configurations
  - `MCPServerConfigEntity` - MCP server configurations
  - `AttachmentEntity` - File attachments
- `KeychainManager.swift` - Secure API key storage (uses `apiKeyKeychainID` pattern)
- `AttachmentStorageManager.swift` - File attachment handling
- `FavoriteModelsStore.swift` - User-favorited models

**Pattern**: Entities store serialized JSON (`Data`) for complex fields (e.g., `contentData`, `modelConfigData`). Use `toDomain()` and `fromDomain()` for conversions.

### **Sources/Networking/** - HTTP & Streaming

- `NetworkManager.swift` - HTTP request handling
- `SSEParser.swift` - Server-Sent Events (SSE) parser for streaming responses
- `PDFKitTextExtractor.swift`, `PDFKitImageRenderer.swift` - Native macOS PDF processing
- `MistralOCRClient.swift` - Mistral OCR API client for PDF/image OCR
- `DeepInfraDeepSeekOCRClient.swift` - DeepSeek OCR via DeepInfra for PDF/image OCR
- `OpenAIAudioClient.swift`, `GroqAudioClient.swift` - Speech-to-Text (Whisper) clients
- `ElevenLabsTTSClient.swift` - Text-to-Speech client
- `MultipartFormDataBuilder.swift` - Helper for multipart/form-data uploads

### **Sources/MCP/** - Model Context Protocol

MCP client implementation for extensible tool/context integrations:

- `MCPHub.swift` - Actor managing MCP server connections and tool routing
  - `toolDefinitions(for:)` - Aggregates tools from enabled servers
  - `executeTool(functionName:arguments:)` - Routes tool calls to correct server
  - Supports long-running servers (persistent connections) vs. ephemeral
- `MCPClient.swift` - Individual MCP server client (spawns processes, handles JSON-RPC)
- `MCPServerConfig.swift` - Server configuration (command, args, env)
- `MCPMessageFraming.swift`, `JSONRPCEnvelope.swift` - Protocol implementation details
- `NPMRCUtils.swift` - npm/npx registry configuration for MCP servers

**Pattern**: Function names are namespaced as `{serverID}__{toolName}` (truncated if >64 chars). Tools are disabled per-server via `disabledTools` array.

### **Sources/Resources/** - Static Assets

Currently empty, reserved for bundled resources like images, sounds, etc.

### **Plugins & Extensions**

Jin supports several optional plugins configured via Settings → Plugins:

#### **PDF Processing**

Three methods for handling PDFs attached to messages:

1. **Native Provider Support** - Some models (Anthropic, OpenAI with vision models) support native PDF input. Jin sends PDFs directly via `data:application/pdf;base64,...`
2. **Mistral OCR** (`MistralOCRClient`) - Uses Mistral's OCR API to extract markdown from PDFs. Requires API key stored in Keychain under `plugin_mistral_ocr`
3. **DeepSeek OCR** (`DeepInfraDeepSeekOCRClient`) - Uses DeepSeek OCR via DeepInfra. Requires API key stored in Keychain under `plugin_deepinfra_deepseek_ocr`
4. **macOS Extract** (`PDFKitTextExtractor`) - Uses PDFKit to extract text locally (no API key needed)

**User Selection**: PDF processing mode is chosen per-attachment via dropdown menu in ChatView. Extracted text is rendered via `AttachmentPromptRenderer.fallbackText()`.

**Error Handling**: `PDFProcessingError` enum handles missing API keys, unsupported models, and extraction failures.

#### **Text-to-Speech (TTS)**

Converts assistant messages to audio playback. Configured via `AppPreferences` and `TextToSpeechPluginSettingsView`.

**Providers** (see `SpeechExtensions.swift`):
- **ElevenLabs** - High-quality voices with fine control (stability, similarity boost, style)
- **OpenAI** - TTS-1/TTS-1-HD with multiple voices
- **Groq** - Fast TTS with Whisper models

**Keychain IDs**: `plugin_elevenlabs_tts`, `plugin_openai_tts`, `plugin_groq_tts`

**Playback**: `TextToSpeechPlaybackManager` handles audio streaming and UI controls.

#### **Speech-to-Text (STT)**

Converts voice recordings to text for user messages. Configured via `SpeechToTextPluginSettingsView`.

**Providers**:
- **OpenAI** - Whisper API with translation support
- **Groq** - Fast Whisper inference

**Keychain IDs**: `plugin_openai_stt`, `plugin_groq_stt`

**Recording**: `SpeechToTextManager` handles microphone capture. Audio file can optionally be attached to message after transcription via `sttAddRecordingAsFile` preference.

## Key Architectural Patterns

### Streaming Architecture

1. **ConversationStreamingStore** (main actor) - Tracks active streaming sessions by conversation ID
2. Adapters return `AsyncThrowingStream<StreamEvent, Error>`
3. UI observes streaming state and accumulates deltas in real-time
4. Streaming continues in background even if user navigates away

### Tool Execution Flow

1. `MCPHub.toolDefinitions()` aggregates tools from enabled MCP servers
2. Tools are passed to adapter's `sendMessage()` via `translateTools()`
3. Provider returns `.toolCallStart/Delta/End` events
4. UI/ChatView executes tools via `MCPHub.executeTool()`
5. Tool results appended as new user message with `role: .tool`

### Credential Management

- API keys stored in Keychain via `KeychainManager`
- `ProviderConfigEntity` references keychain via `apiKeyKeychainID`
- `ProviderManager` resolves credentials (checks inline `apiKey` first, then keychain)
- Plugin credentials use dedicated keychain IDs:
  - PDF OCR: `plugin_mistral_ocr`, `plugin_deepinfra_deepseek_ocr`
  - TTS: `plugin_elevenlabs_tts`, `plugin_openai_tts`, `plugin_groq_tts`
  - STT: `plugin_openai_stt`, `plugin_groq_stt`

### Thinking Blocks (Reasoning Models)

- `.thinking(ThinkingBlock)` - OpenAI reasoning text or Anthropic thinking with optional signature
- `.redactedThinking(RedactedThinkingBlock)` - Provider-redacted reasoning
- `thinkingVisible` flag on `MessageEntity` controls visibility in UI

## Swift Concurrency

Jin heavily uses Swift concurrency:

- **Actors**: `ProviderManager`, `MCPHub`, `MCPClient`, `LLMProviderAdapter` protocol
- **async/await** throughout networking and adapter layers
- **AsyncThrowingStream** for streaming responses
- **@MainActor** for `ConversationStreamingStore` and SwiftUI views

## Dependencies (Package.swift)

- **MarkdownView** (2.5.2+) - Markdown rendering with syntax highlighting
- **MCP Swift SDK** (0.10.0+) - Model Context Protocol client library

## Testing

- Framework: XCTest
- Location: `Tests/JinTests/`
- Pattern: `*Tests.swift` files, `final class FooTests: XCTestCase`
- Focus: Unit tests for Domain, Networking, Persistence; avoid network-dependent tests

## Development Workflow

### Adding a New Provider

1. Create `Sources/Adapters/NewProviderAdapter.swift` implementing `LLMProviderAdapter`
2. Add case to `ProviderType` enum in `GenerationControls.swift`
3. Add factory case in `ProviderManager.createAdapter(for:)`
4. Test with `swift build && swift run Jin`

### Adding a New Plugin

Plugins extend Jin with optional features (OCR, TTS, STT):

1. **Create client actor** in `Sources/Networking/` (e.g., `NewPluginClient.swift`)
2. **Define keychain ID** as a constant (e.g., `plugin_newfeature`)
3. **Add preferences keys** to `AppPreferenceKeys` in `AppPreferences.swift`
4. **Create settings UI** in `Sources/UI/` (e.g., `NewPluginSettingsView.swift`)
5. **Integrate in SettingsView.swift** under "Plugins" section
6. **Add error cases** to relevant error enums (e.g., `PDFProcessingError`, `SpeechExtensionError`)

**Plugin Pattern**: Plugins are optional, user-configured features that require API keys stored securely in Keychain. They extend core functionality without blocking basic app usage.

### Adding MCP Server Support

Default MCP servers are seeded in `JinApp.seedDefaultMCPServersIfNeeded()`. To add:

1. Add `seedIfMissing()` call with server config (command, args, env)
2. Set `isEnabled: false` (user enables in Settings)
3. Set `isLongRunning: true` for persistent servers, `false` for ephemeral

### Modifying Message Content

- Update `ContentPart` enum in `Message.swift` for new content types
- Update `ContentPart.encode/decode` for Codable conformance
- Update UI rendering in `MessageTextView.swift` or equivalent

## Packaging

The `Packaging/package.sh` script:

1. Builds release binary (`swift build -c release`)
2. Creates `.app` bundle structure
3. Copies binary to `dist/Jin.app/Contents/MacOS/`
4. Optionally creates `.dmg` installer

## Code Style

- **Indentation**: 4 spaces (no tabs)
- **Naming**:
  - Views: `*View`
  - Entities: `*Entity`
  - Adapters: `*Adapter`
- **File organization**: One primary type per file, filename matches type name
- **Concurrency**: Prefer `actor` for shared mutable state, `@MainActor` for UI-bound state

## Security

- **Never commit secrets**: Use Keychain for all API keys (provider and plugin keys)
- **Avoid logging sensitive data**: Don't log request/response payloads in adapters or plugin clients
- **Validate provider responses**: Check for malformed tool calls, injection attempts in tool arguments
- **Plugin key isolation**: Each plugin uses dedicated keychain ID to prevent key reuse/confusion

## ⚠️ CRITICAL: SwiftData Persistence Issues (Lessons Learned)

### Problem: Data Not Persisting in SwiftUI Forms

**Symptom**: User edits fields in `AssistantInspectorView` but changes don't save to database.

**Root Cause**: SwiftData requires explicit context injection and save calls when using `@Bindable` in child views.

**Solution**:

```swift
// ❌ WRONG - Changes won't persist
private struct SettingsEditor: View {
    @Bindable var assistant: AssistantEntity

    var nameBinding: Binding<String> {
        Binding(
            get: { assistant.name },
            set: { newValue in
                assistant.name = newValue  // NOT SAVED!
            }
        )
    }
}

// ✅ CORRECT - Must inject modelContext and call save()
private struct SettingsEditor: View {
    @Bindable var assistant: AssistantEntity
    @Environment(\.modelContext) private var modelContext  // REQUIRED!

    var nameBinding: Binding<String> {
        Binding(
            get: { assistant.name },
            set: { newValue in
                assistant.name = newValue
                assistant.updatedAt = Date()
                try? modelContext.save()  // MUST CALL SAVE!
            }
        )
    }
}
```

**Files Affected**: `AssistantInspectorView.swift`

**All Settings That Must Call `try? modelContext.save()`**:

- ✅ `nameBinding` - Assistant name
- ✅ `iconBinding` - Assistant icon
- ✅ `descriptionBinding` - Assistant description
- ✅ `systemInstructionBinding` - System prompt
- ✅ `temperatureBinding` - Temperature slider
- ✅ `maxOutputTokensBinding` - Max output tokens (with Clear button when set)
- ✅ `truncateMessagesSettingBinding` - Truncate history (Default/On/Off)
- ✅ `maxHistoryMessagesBinding` - Max messages to keep (shown when Truncate = On)
- ✅ `replyLanguageSelectionBinding` - Reply language
- ✅ Custom reply language TextField onChange handler

### Problem: TextField Placeholders Not Showing

**Symptom**: TextField shows "Assistant name" or "Brief description" as actual text instead of placeholder.

**Root Cause**: Using old TextField API where first parameter is the label, not placeholder.

**Solution**:

```swift
// ❌ WRONG - First param is label, not placeholder
TextField("Assistant name", text: nameBinding)

// ✅ CORRECT - Use prompt parameter for placeholder
TextField(text: nameBinding, prompt: Text("e.g., Code Assistant")) {
    EmptyView()
}
```

### Problem: Max Tokens Shows Useless "Default" Placeholder

**Symptom**: Max Tokens field always shows "Default" even when user types a value.

**Root Cause**: Using placeholder text instead of showing actual value or clear indication.

**Solution**:

```swift
// Display current value or "No limit"
HStack {
    Text("Max Output Tokens")
    Spacer()
    if let tokens = assistant.maxOutputTokens {
        Text("\(tokens)")  // Show actual value
    } else {
        Text("No limit")   // Show clear status
    }
}

// TextField with proper placeholder
TextField(text: binding, prompt: Text("e.g., 4096")) {
    EmptyView()
}

// Add Clear button when value is set
if assistant.maxOutputTokens != nil {
    Button("Clear") {
        assistant.maxOutputTokens = nil
        try? modelContext.save()
    }
}
```

### Problem: Truncate History Has No User Control

**Symptom**: User can turn truncation On/Off, but cannot control HOW MUCH to truncate.

**Root Cause**: Missing `maxHistoryMessages` field and UI control.

**Solution**:

1. **Add field to AssistantEntity**:

```swift
@Model
final class AssistantEntity {
    var truncateMessages: Bool?
    var maxHistoryMessages: Int?  // NEW FIELD
}
```

2. **Add UI when Truncate = On**:

```swift
if truncateMessagesSettingBinding.wrappedValue == .on {
    HStack(spacing: 8) {
        Text("Keep last")
        TextField(text: maxHistoryMessagesBinding, prompt: Text("50")) {
            EmptyView()
        }
        .frame(maxWidth: 80)
        Text("messages")
    }
}
```

3. **Apply in ChatView**:

```swift
// First truncate by message count
if let maxMessages = maxHistoryMessages, shouldTruncateMessages {
    let systemMessages = history.prefix(while: { $0.role == .system })
    let nonSystemMessages = history.drop(while: { $0.role == .system })
    let kept = Array(nonSystemMessages.suffix(maxMessages))
    history = Array(systemMessages) + kept
}

// Then apply token-based truncation
if shouldTruncateMessages {
    history = ChatHistoryTruncator.truncatedHistory(
        history,
        contextWindow: modelContextWindow,
        reservedOutputTokens: reservedOutputTokens
    )
}
```

### Testing Checklist for Settings UI

When modifying Assistant settings or any SwiftData-backed form:

1. **Test each field individually**:
   - Change value
   - Close and reopen settings
   - Verify change persisted

2. **Test edge cases**:
   - Empty values (should save as nil where appropriate)
   - Very long text
   - Special characters
   - Emoji in text fields

3. **Verify database updates**:
   - Check `assistant.updatedAt` timestamp changes
   - Verify changes appear in sidebar immediately
   - Start new chat to confirm defaults are applied

4. **Test all pickers and segmented controls**:
   - Truncate History: Default/On/Off all work
   - Reply Language: All preset languages + Custom
   - Icon Picker: Choose icon, verify it appears in header and sidebar

### Production Quality Standards

**This is a $100/year subscription product. Every feature MUST:**

- ✅ Actually save data to database
- ✅ Show correct placeholders, not labels
- ✅ Update UI immediately after changes
- ✅ Work on first try (no "refresh needed")
- ✅ Handle edge cases (empty, nil, special chars)
- ✅ Be tested manually before committing

**Never assume SwiftUI "just works" - always verify persistence manually.**
Never write unnecessary bullshit docs.
