# Tests for a new model

Deterministic unit tests only. No live network in CI.

## Always add

### 1. Catalog exact ID — `Tests/JinTests/ModelCatalogTests.swift`

Assert `ModelCatalog.modelInfo(for:id, provider:)`:

- `name` / display
- `contextWindow`
- `maxOutputTokens` (or `nil`)
- `capabilities` equality, not “contains”
- `reasoningConfig` type + default
- seeded list contains / does not contain the ID as intended

### 2. Similar-ID conservative fallback — same file

```swift
let custom = ModelCatalog.modelInfo(for: "<id>-custom", provider: .<provider>)
XCTAssertEqual(custom.capabilities, [.streaming, .toolCalling])
XCTAssertEqual(custom.contextWindow, 128_000)
XCTAssertNil(custom.maxOutputTokens)
XCTAssertNil(custom.reasoningConfig)
XCTAssertFalse(JinModelSupport.isFullySupported(providerType: .<provider>, modelID: "<id>-custom"))
```

### 3. Fully-supported exact match — `JinModelSupportTests.swift`

True for the exact ID, false for `id-custom` and for a gateway ID missing the required prefix.

Cover `openaiWebSocket` separately when the OpenAI record is non-streaming (Pro models are not fully-supported on WebSocket).

### 4. Resolver catalog fallback — `ModelSettingsResolverTests.swift`

Build a **stale** `ModelInfo` with the new ID but old/low capabilities and no `overrides`. Resolve with the real `providerType`. Expect catalog context, max output, reasoning, and capabilities.

This is the legacy persisted-model case `AGENTS.md` requires.

### 5. Registry — `ModelCapabilityRegistryTests.swift`

If you changed an allowlist, assert:

- `supportedReasoningEfforts(for:modelID:)` exact band
- `supportsOpenAIStyleMaxEffort` / verbosity / pro mode
- `supportsWebSearch` / `supportsCodeExecution` / `supportsGoogleMaps`
- a near-miss ID does **not** inherit the band

## Add when the surface exists

| Surface | Suite |
| --- | --- |
| Anthropic thinking / fast / sampling | `AnthropicOpus5SupportTests`, `AnthropicAdapterFastModeTests`, `AnthropicRequestBodySupportTests` |
| OpenAI Responses knobs | `OpenAIResponsesGPT56ControlsTests`, `OpenAIResponsesRequestSupportTests` |
| OpenAI image | `OpenAIImageModelSupportTests` |
| Gemini thinking / sampling / PDF | `GeminiAdapterTests`, `Gemma4ProviderSupportTests`, `VertexAIModelSupportTests` |
| xAI media / always-on reasoning | `XAIModelSupportTests`, `XAIAdapterMediaTests` |
| OpenCode Go routing / videoInput | `ModelCatalogTests.testOpenCodeGoVideoInputClaimsMatchLiveProbedModels` + adapter tests |
| OpenRouter videoInput | `ModelCatalogTests.openRouterVideoInputVerifiedModelIDs` — **update only after a live probe** |
| Gateway prefixed IDs | `JinModelSupportTests` Cloudflare/Vercel cases |
| Fireworks dual IDs | both `fireworks/…` and `accounts/fireworks/models/…` |
| Request body | `AdapterRequestConstructionTests`, `*RequestSupportTests` |
| Composer / settings UI helpers | `ChatModelCapabilitySupportTests`, `ModelSettingsSheetSupportTests` |
| Preferred picker order | `ChatModelSelectionSupport` tests if present |

## Anti-patterns

- Do not assert prefix matches (`hasPrefix("gpt-5")`) in new tests.
- Do not weaken `testOpenRouterVideoInputClaimsMatchLiveProbedModels` to make a catalog compile.
- Do not test live HTTP in unit tests.

## Commands

```bash
swift test --filter ModelCatalogTests
swift test --filter JinModelSupportTests
swift test --filter ModelCapabilityRegistryTests
swift test --filter ModelSettingsResolverTests
swift test --filter <ProviderOrSurface>Tests
```
