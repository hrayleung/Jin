# Repository Guidelines

## Project Structure & Module Organization

- `Package.swift` defines a Swift Package Manager (SPM) executable target (`Jin`) for macOS 14+.
- `Sources/` contains production code, organized by layer:
  - `Sources/UI/` — SwiftUI entry point and views.
  - `Sources/Domain/` — domain models (messages, tools, generation controls).
  - `Sources/Adapters/` — LLM provider adapters and routing (e.g., `OpenAIAdapter.swift`).
  - `Sources/Networking/` — HTTP + streaming helpers (e.g., `SSEParser.swift`).
  - `Sources/Persistence/` — SwiftData models and storage utilities (Keychain/attachments).
  - `Sources/Resources/` — app resources (e.g., `Info.plist`).
- `Tests/JinTests/` contains XCTest-based unit tests.

## Build, Test, and Development Commands

- `swift build` — compile the package.
- `swift run Jin` — run the app from the command line.
- `swift test` — run all unit tests.
- Xcode: open `Package.swift` and run the `Jin` scheme for local UI development.

## Coding Style & Naming Conventions

- Use 4-space indentation (no tabs) and follow Swift API Design Guidelines.
- Prefer one primary type per file; keep file names aligned with the main type.
- Naming patterns used in this repo:
  - SwiftUI views: `*View` (e.g., `ChatView`).
  - SwiftData models: `*Entity` (e.g., `ConversationEntity`).
  - Provider integrations: `Sources/Adapters/*Adapter.swift`.

## Testing Guidelines

- Framework: XCTest (`import XCTest`).
- Conventions: `*Tests.swift` files, `final class FooTests: XCTestCase`, `func testSomething()`.
- Keep tests deterministic (avoid real network calls); prefer unit tests for Domain/Networking/Persistence logic.

## UI & Packaging Checklist

- When adding a new model, always check whether related parameter controls and capability UI must be updated (e.g., reasoning, web search, provider-specific options).
- When changing functionality, always verify whether corresponding UI behavior/text/options must be updated.
- UI/UX must follow elegant, user-first design principles: prioritize clarity, accessibility, and coherent interaction flow over feature-completeness alone.
- Design decisions for screens, states, and micro-interactions should start from expected user intent and reduce cognitive load.
- If UI/UX intent or interaction pattern is unclear, verify against reliable references (e.g., Apple HIG / established UI conventions) before implementation; avoid guessing.
- After code changes are complete, run `bash Packaging/package.sh` once to produce a packaged build.

## Commit & Pull Request Guidelines

- This checkout may not include Git history; use a simple Conventional Commits style:
  - `feat: ...`, `fix: ...`, `refactor: ...`, `test: ...`, `docs: ...`
- PRs should include: a short summary, rationale, how to verify (`swift test`, `swift run Jin`), and screenshots for UI changes.
- Don’t commit generated or local-only artifacts (e.g., `.build/`, `.swiftpm/`, `.DS_Store`, `.claude/settings.local.json`).

## Security & Configuration Tips

- Never commit API keys or tokens. Provider credentials should be stored via Keychain and referenced indirectly (see `ProviderConfigEntity.apiKeyKeychainID`).
- Avoid logging sensitive request/response payloads when adding or debugging providers.
