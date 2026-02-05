# Jin - Native macOS LLM Client

## Project Overview

**Jin** is a native macOS application designed to interact with multiple Large Language Model (LLM) providers, including OpenAI, Anthropic, xAI, and Vertex AI. Built with SwiftUI and SwiftData, it offers a modern, responsive user interface for managing conversations, configuring providers, and handling rich multimodal content (text, images, audio, files).

### Key Features
-   **Multi-Provider Support:** Seamlessly switch between OpenAI (GPT-4o, GPT-5.2), Anthropic (Claude Sonnet/Opus/Haiku), xAI, and Vertex AI.
-   **Rich Content:** Supports text, images, file attachments, and audio input/output.
-   **Advanced Reasoning:** Displays "Thinking" blocks for reasoning models.
-   **Tool Use:** Integrated support for LLM tool calling and execution.
-   **MCP Integration:** Implements the Model Context Protocol (MCP) for extensible context management.
-   **Privacy-Focused:** API keys are stored securely in the macOS Keychain; conversation history is stored locally using SwiftData.

## Architecture

The project follows a modular architecture organized by layer:

-   **`Sources/UI/`**: Contains the SwiftUI views and app entry point (`JinApp.swift`).
    -   **Pattern:** Views are named `*View` (e.g., `ChatView`, `SettingsView`).
    -   **Entry:** `JinApp` initializes the SwiftData `ModelContainer` and the main window group.
-   **`Sources/Domain/`**: Defines the core business logic and data models (e.g., `Message`, `ContentPart`, `GenerationControls`).
    -   **`Message.swift`**: The central data structure for chat history, supporting multimodal content and tool calls.
-   **`Sources/Adapters/`**: Handles provider-specific logic and API translation.
    -   **`ProviderManager`**: Factory and manager for creating provider adapters.
    -   **`*Adapter.swift`**: Implementations for specific providers (e.g., `OpenAIAdapter`, `AnthropicAdapter`).
-   **`Sources/Persistence/`**: Manages local storage.
    -   **SwiftData:** Used for `ConversationEntity`, `MessageEntity`, etc.
    -   **`KeychainManager`**: Securely stores API keys and service account credentials.
-   **`Sources/Networking/`**: Shared networking utilities.
    -   **`NetworkManager`**: Handles HTTP requests.
    -   **`SSEParser`**: Parses Server-Sent Events for streaming responses.
-   **`Sources/MCP/`**: Implementation of the Model Context Protocol client and hub.

## Building and Running

### Prerequisites
-   macOS 14 (Sonoma) or later.
-   Swift 5.9+.

### CLI Commands
*   **Build:** `swift build`
*   **Run:** `swift run Jin`
*   **Test:** `swift test` (Runs XCTest suite in `Tests/JinTests/`)

### Packaging
Use the provided script to create a release `.app` bundle or `.dmg`:
```bash
# Create .app bundle in dist/
./Packaging/package.sh

# Create .dmg installer
./Packaging/package.sh dmg
```

## Development Guidelines

### Coding Style
-   **Indentation:** 4 spaces (no tabs).
-   **Structure:** One primary type per file, with the filename matching the type name.
-   **Concurrency:** Heavy use of Swift Concurrency (`async`/`await`, `actor`).
-   **Formatting:** Follow standard Swift API Design Guidelines.

### Testing
-   **Framework:** XCTest.
-   **Location:** `Tests/JinTests/`.
-   **Philosophy:** Prefer unit tests for Domain, Networking, and Persistence logic. Avoid network-dependent tests in the main suite.

### Configuration
-   **Secrets:** Never commit API keys. Use the in-app Settings to configure providers, which saves credentials to the Keychain.
-   **Default Providers:** The app bootstraps default configurations for OpenAI, Anthropic, xAI, and Vertex AI on the first run.

## Resources
-   **`AGENTS.md`**: Detailed repository guidelines, architectural rules, and prompt instructions for AI agents.
-   **`Package.swift`**: Swift Package Manager configuration.
