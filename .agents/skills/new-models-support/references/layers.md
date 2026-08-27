# Layer map — every new model must walk this list

`ModelCatalog` is the source of truth for capabilities, context, max output, reasoning config, and ✦ fully-supported. Adapters and UI must not invent string-matching heuristics on top.

Unknown IDs always fall back to `[.streaming, .toolCalling]`, 128_000 context, no max output, no reasoning (`ModelCatalog.fallbackModelInfo`).

## 1. Catalog records

Register in `Sources/Domain/ModelCatalogRecords.swift` `orderedRecords` only when adding a **new provider**. For a new model, edit the existing array:

| Provider | File | `static let` |
| --- | --- | --- |
| OpenAI (+ WebSocket mirror) | `ModelCatalogRecords+OpenAI.swift` | `openAIRecords` |
| Cloudflare AI Gateway | same | `cloudflareAIGatewayRecords` |
| Vercel AI Gateway | same | `vercelAIGatewayRecords` |
| Gemini, Vertex, OpenRouter | `ModelCatalogRecords+Google.swift` | `geminiRecords`, `vertexAIRecords`, `openRouterRecords` |
| Anthropic, Perplexity, DeepInfra, Together, xAI, DeepSeek, Zhipu, MiniMax, Fireworks, Groq, Cerebras, SambaNova, MiMo, Kimi for Coding, OpenCode Go, Meta, MorphLLM, Baseten, Modal | `ModelCatalogRecords+Independent.swift` | matching `*Records` |
| Mistral | `ModelCatalogRecords+Mistral.swift` | `mistralRecords` |
| Databricks | `ModelCatalogRecords+Databricks.swift` | `databricksRecords` |
| Makora | `ModelCatalogRecords+Makora.swift` | `makoraRecords` |
| Ramp Router | `ModelCatalogRecords+Router.swift` | `routerRecords` |
| RunInfra | `ModelCatalogRecords+RunInfra.swift` | `runinfraRecords` |
| Zyphra | `ModelCatalogRecords+Zyphra.swift` | `zyphraRecords` |

`claudeManagedAgents` **reuses** `anthropicRecords`. Do not fork a second Claude list unless the managed-agent runtime truly diverges.

Record shape:

```swift
Record(
    id: "exact-api-id",
    displayName: "Human Name",
    capabilities: [.streaming, .toolCalling, /* … */],
    contextWindow: 1_000_000,
    maxOutputTokens: 128_000,          // omit if undocumented
    reasoningConfig: ModelReasoningConfig(type: .effort, defaultEffort: .medium),
    isFullySupported: true,
    isSeeded: true
)
```

`ModelCapability` bits: `streaming`, `toolCalling`, `vision`, `audio`, `reasoning`, `promptCaching`, `nativePDF`, `imageGeneration`, `videoGeneration`, `codeExecution`, `videoInput`.

`reasoningConfig` must be non-nil **only** when `.reasoning` is set. Types: `.effort`, `.budget`, `.toggle`, `.none`.

Comment the official URL and verification date above the record. Group dated snapshots next to the unversioned alias.

## 2. Seeds and Add Model

- `Sources/Domain/DefaultProviderSeeds.swift` — first-launch models come from `ModelCatalog.seededModels(for:)`. No extra seed list unless you add a provider.
- `Sources/UI/AddModelSheet.swift` → `ModelCatalog.modelInfo(for:provider:name:)` — typing the exact ID must pick up the new record.
- Adapter `fetchAvailableModels()` must call `ModelCatalog.modelInfo` / `entry` for known IDs (`*Adapter+ModelCatalog.swift`, `OpenAICompatibleModelMappingSupport.swift`).

## 3. Capability registry (exact-ID allowlists)

`Sources/Domain/ModelCapabilityRegistry.swift`

Touch only the sets that the evidence sheet requires. Typical:

- OpenAI effort: `openAINoneDefaultReasoningModelIDs`, `openAIHighDefaultReasoningModelIDs`, `openAIStyleExtremeEffortModelIDs`, `openAIStyleMaxEffortModelIDs`, `openAIStyleProModeModelIDs`, `openAIStyleReasoningContextModelIDs`, `openAIStyleVerbosityModelIDs`
- Gemini thinking bands: `gemini3FlashEffortModelIDs`, `gemini37FlashEffortModelIDs`, `gemini31FlashImageEffortModelIDs`, `gemini31ProEffortModelIDs`, `gemini3ProLowHighEffortModelIDs`
- Google Search / Maps / code execution sets (Gemini vs Vertex vs OpenRouter are **different lists**)
- `supportsWebSearch`, `supportsCodeExecution`, `supportsGoogleMaps`, `supportsWebSearchDynamicFiltering`
- `supportedReasoningEfforts(for:modelID:)` — add a `case .provider where set.contains` arm with the **exact** band the API accepts
- `supportsOpenAIStyleMaxEffort` — provider-first so one host's slug cannot grant `max` on another

Do not reuse OpenAI sets for Router; Router has its own ID sets and rejects out-of-band effort with HTTP 400.

## 4. Settings resolver (legacy + always-on)

`Sources/Domain/ModelSettingsResolver.swift`

- Catalog values win over stale persisted `ModelInfo` when the user has no `overrides`.
- Add the exact ID to the provider's `*AlwaysOnReasoningModelIDs` when Off is illegal (xAI grok-4.6, GLM-5.3, Muse Spark, Qwen3.8-2.4T, …).
- Meta Muse Spark: provider-wide `reasoningCanDisable = false`.
- Router: derived from the published effort band (Off only if the band includes `.none`).

Also check `Sources/Domain/LegacyOpenAIMaxOutputMigration.swift` if OpenAI max-output defaults change.

## 5. Provider-specific support files

Update **only** the files whose behavior is ID-gated:

| Surface | File |
| --- | --- |
| Anthropic thinking / effort / fast mode / sampling / max output | `Sources/Domain/AnthropicModelLimits.swift` |
| OpenAI image gen families + UI options | `Sources/Domain/OpenAIImageModelSupport.swift` |
| xAI image/video gen + chat reasoning | `Sources/Adapters/XAIModelSupport.swift` |
| Gemini/Vertex known IDs, sampling, image gen, native PDF | `Sources/Adapters/GeminiModelConstants.swift`, `Sources/Adapters/VertexAIModelSupport.swift` |
| OpenAI Responses `temperature`/`top_p` | `Sources/Adapters/AdapterModelCapabilities.swift` (`openAIResponsesSamplingAllowedModelIDs`) |
| OpenAI audio input IDs | same file + `Sources/UI/ChatViewModelIDs.swift` |
| OpenCode Go endpoint routing + temperature lock | `Sources/Adapters/OpenCodeGoAdapter.swift` |
| Makora reasoning | `Sources/Adapters/MakoraModelSupport.swift` |
| MiMo IDs | `Sources/Domain/MiMoModelIDs.swift` |
| Modal endpoint IDs | `Sources/Domain/ModalEndpointSupport.swift` |
| Together / OpenRouter video gen controls | `TogetherVideoGenerationControls.swift`, `OpenRouterVideoGenerationControls.swift` |

Anthropic `isModelFamily(prefix:)` already matches date-suffixed snapshots of a prefix. **Fast mode is exact-match only** (`claude-opus-5`, `claude-opus-4-8`). Do not extend fast mode by prefix — date-suffixed IDs 400 and still bill.

OpenCode Go routing sets are exact ID, never `minimax-*` / `qwen*` prefix. A new MiniMax/Qwen ID that should go to `/messages` must be added to `anthropicMessagesModelIDs` or it will hit the wrong endpoint. `.videoInput` is invalid on `/messages` even if the weights accept video on `/chat/completions`.

## 6. Adapter request builders

If the model needs a new parameter, a forbidden parameter, or a different endpoint:

- `Sources/Adapters/<Provider>RequestSupport.swift`
- OpenAI Responses: `OpenAIResponsesRequestSupport.swift`
- Gemini: `GeminiRequestSupport.swift`, `VertexAIRequestBuilder+GenerationConfig.swift`
- Anthropic: `AnthropicRequestBodySupport.swift`, `AnthropicThinkingConfigSupport.swift`
- Sampling strippers in `OpenAICompatibleRequestSupport.swift`, `OpenRouterRequestSupport.swift`, `DatabricksRequestSupport.swift`, `RouterRequestSupport.swift`

A 400 from an extra field is a support bug. Prefer omitting undocumented fields.

## 7. UI / composer / picker

Drift hotspot: `Sources/UI/ChatViewModelIDs.swift` duplicates image/video/audio ID sets. Keep it in sync with the Domain/Adapter source of truth, or reference that source.

Also check:

- `Sources/UI/ChatModelSelectionSupport.swift` — `preferred*ModelOrder` (flagship new IDs go first; use an ordered list, not a long `??` chain)
- `Sources/UI/ContentView+ConversationModelResolution.swift` — `absoluteFallbackModelIDs`
- `Sources/UI/ChatAttachmentCapabilitySupport.swift` — native PDF sendability, image/video gen detection
- `Sources/UI/ChatView+ModelCapabilities.swift` / `ChatView+ModelControls.swift` — control visibility
- Composer help text and settings labels if a control is new or removed
- `JinModelSupport.fullSupportSymbol` (✦) via `ModelCatalog.isFullySupported`

UI rule from `AGENTS.md`: elegant, user-first; do not expose a knob the model rejects.

## 8. Tests (required)

See [tests.md](tests.md). At minimum extend `ModelCatalogTests`, `JinModelSupportTests`, `ModelCapabilityRegistryTests`, and `ModelSettingsResolverTests`.

## Sync grep

After editing, run:

```bash
bash .agents/skills/new-models-support/scripts/scan-model-id.sh '<exact-id>'
```

Every hit should be an intentional exact-ID site. If you only see the catalog row, you missed layers.

## Out of scope unless asked

- New **provider** (follow `CLAUDE.md` “Adding a new provider”, ~15 sites)
- Speech TTS/STT catalogs
- MCP servers
