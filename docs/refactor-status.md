# Refactor Program Status

Phased elegance / performance / productivity refactor on branch `refactor`.
Behavior-preserving; native markdown + AppKit timeline retained.

## Completed

| Phase | Deliverable |
|-------|-------------|
| **0** | `ModelCatalogConsistencyTests`, perf checklist |
| **1a–1c** | `ModelFeatures` + OpenAI / Anthropic / Gemini / Vertex feature tables; registry dual-read SSoT |
| **2** | `OpenAICompatibleProfile` wired through thin chat-completions adapters |
| **3a** | Chunk-scan SSE / JSONL parsers |
| **3b** | Streaming artifact parse fast-path; longer flush intervals |
| **3c** | Snapshot capture without MainActor sort; decode stays on detached task |
| **3d** | ImageIO draft thumbnails + cache cost limits |
| **3e** | Tool / search / code-exec UI coalesced into flush buffer (one MainActor hop) |
| **4a** | `ChatSessionModel` for controls, drafts, MCP selection, errors |
| **4b** | `GenerationControlsNormalizer` domain clamp used by UI + resolver |

## Intentionally deferred

| Item | Why |
|------|-----|
| Full SPM split (`JinDomain` / `JinAdapters` / `JinUI`) | High merge cost; do when compile isolation becomes the top pain |
| Sheet-draft mega-state into session | Low re-render impact vs controls/drafts; incremental follow-up |
| Full Gemini/Vertex adapter merge | Shared cores already exist; full merge ROI lower than profiles |
| Typed `ProviderExtras` bag replacement | Wide Codable surface; after feature-table migration settles |

## New model golden path (current)

1. Add / update `ModelCatalog.Record` (and feature table row when wire flags needed)
2. `swift test --filter ModelCatalogConsistencyTests`
3. UI/adapters resolve via `ModelCatalog` / `ModelCapabilityRegistry` / `JinModelSupport`

## Verification hotspots

```bash
swift test --filter ModelCatalogConsistencyTests
swift test --filter StreamingMessageStateTests
swift test --filter StreamingUIFlushBufferTests
swift test --filter OpenAICompatibleProfileTests
swift test --filter ImageThumbnailSupportTests
swift test --filter ChatCompletionsAdaptersTests
```

Manual: `docs/refactor-perf-checklist.md`
