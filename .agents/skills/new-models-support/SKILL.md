---
name: new-models-support
description: "Discover newly released LLM, image, and video models from official provider docs and add complete Jin support (catalog, exact-ID capabilities, adapters, UI controls, tests). Use when adding or updating a model ID, scanning for latest models, fixing model metadata, or when the user says 新模型, 最新模型, 完美支持, or support this model."
---

# New Models Support

Add or refresh Jin model support from **official, per-ID documentation**. Guessing from a family name, a blog title, OpenRouter modalities, or `models.dev` is a bug.

This skill covers chat / reasoning / image-generation / video-generation models in `ModelCatalog`. Speech plugin catalogs (`SpeechProviderModelCatalog`, `SpeechModelCapabilityRegistry`) are out of scope unless the user explicitly asks.

## Inputs

Accept any of:

- One or more **exact API model IDs** plus provider (`openai` / `gpt-5.6-sol`)
- A provider scan (`scan Anthropic and Gemini`)
- An undirected scan (`support the latest models`)

If the user names a **product** (`GPT-5.7`, `Claude 5`, `Grok 5`) and not an API ID, resolve the live slug from official docs before writing code. Do not invent hyphens, date suffixes, or gateway prefixes.

If the task is scan-only, stop after the gap report. Otherwise implement every candidate with a complete evidence sheet, and leave incomplete ones conservative / unseeded / not fully-supported.

## Hard rules

Copy these; they override convenience:

1. **Exact IDs only.** Fully-supported badges, capability defaults, effort bands, web search, code execution, native PDF, sampling gates, and endpoint routing must match the exact catalog ID (case-insensitive lookup is fine; prefix/substring classification is not). A `…-custom` or `…-preview` sibling that is not in the catalog must keep the conservative unknown fallback: streaming + tool calling, 128k context, no reasoning.
2. **Official docs for that exact ID.** Read the model page, the API parameter page, and any changelog/deprecation note. Do not copy another version's limits or parameter set (`gpt-5.4` ≠ `gpt-5.6-sol`; Veo 3 ≠ Veo 3.1; Opus 4.7 ≠ Opus 5).
3. **Do not guess.** If a field is undocumented, leave it conservative (`maxOutputTokens` nil, capability off, effort band narrow, `isFullySupported: false`) and record the gap in a catalog comment with `unverified` + date.
4. **Do not copy across providers.** The same weights on OpenAI, OpenRouter, Cloudflare, Vercel, Fireworks, Together, and OpenCode Go are different IDs with different request shapes, effort bands, and often different context/PDF/video behavior. Look up **that provider's** slug and docs / live `/models`.
5. **Never claim `.videoInput` from a modality table.** `models.dev`, OpenRouter `architecture.input_modalities`, and vendor marketing all lie. Capability is `(model, endpoint)`. A live probe that names known colours in a synthetic clip is required before setting `.videoInput`. See `ModelCatalogTests.openRouterVideoInputVerifiedModelIDs`.
6. **Never mark ✦ fully-supported unless Jin can actually send the documented surface** (right endpoint, right parameters, UI controls that will not 400). Gateway native PDF stays off unless the adapter can put `application/pdf` on the wire.
7. **Sync every layer in one change.** Catalog + capability registry + adapter request/catalog mapping + UI ID sets + settings resolver (including always-on / legacy fallback) + tests. See [references/layers.md](references/layers.md).
8. **Do not add new prefix/substring heuristics.** Existing `openai/` and `google/` canonicalization only strips a gateway prefix from an ID that is already an exact allowlisted slug.

## Workflow

Run from the Jin repo root (`Package.swift` present).

### 1. Inventory what Jin already knows

```bash
python3 .agents/skills/new-models-support/scripts/list-catalog-ids.py
python3 .agents/skills/new-models-support/scripts/list-catalog-ids.py --provider openai
bash .agents/skills/new-models-support/scripts/scan-model-id.sh 'gpt-5.6-sol'
```

Read the current record and nearby comments in the matching `Sources/Domain/ModelCatalogRecords+*.swift` file. Mirror the local comment style (source URL + verification date).

### 2. Search official sources (mandatory)

Do **not** start from GitHub issues, Twitter, or `models.dev`.

Preferred live search, in order:

1. `pplx` CLI if installed (`pplx search web` / `pplx content fetch`) — see the `pplx-cli` skill.
2. Otherwise WebSearch + WebFetch / `curl` the official pages.
3. Provider `GET /v1/models` (or equivalent) only as a **slug confirmation**, and only with a key the user already has. Never commit keys. Router **must** use live `/v1/models`; do not use `docs.router.com/supported-models`.

Search queries to run per provider (replace the family name with what you are hunting):

- `"<model>" site:<official-docs-host> model id context window`
- `"<model>" API "model id" OR "model code"`
- `"<model>" reasoning_effort OR thinking_level OR thinking`
- `"<model>" changelog OR deprecat`

Fetch the **model page** and the **API request page**. Cross-check: if a plan or aggregator says a parameter exists, confirm it on the official page for that ID.

Canonical starting URLs and ID conventions: [references/providers.md](references/providers.md).

Treat as **hints only** (never sole evidence): `models.dev`, OpenRouter model cards, Hugging Face, blogs. Use them to find the official page, then verify.

### 3. Fill an evidence sheet before any code

Use [references/evidence-sheet.md](references/evidence-sheet.md). One sheet per `(provider, exact ID)`.

A sheet is complete only when every of these is either a cited value or an explicit `unknown → conservative`:

- Exact wire `model` / `id` string (and dated snapshot / alias IDs)
- Context window and max output
- Input/output modalities (text, image, audio, video, PDF)
- Tools, web search, code execution, prompt caching
- Reasoning: type (`effort` / `budget` / `toggle` / none), allowed values, default, whether Off is legal
- Sampling: are `temperature` / `top_p` / `top_k` accepted? always? only when reasoning is off?
- Request shape: Responses vs chat/completions vs Anthropic messages vs Gemini `generateContent`
- Provider-only knobs: verbosity, `reasoning.mode=pro`, Anthropic `speed`, Gemini thinking levels, Maps, image/video gen params
- Whether Jin's adapter can actually emit native PDF / video / those knobs

If the ID is not live in the API yet, do not add it. Catalog-only retired IDs are for **already persisted** chats, not for seeding.

### 4. Decide support grade

| Grade | When | Catalog flags |
| --- | --- | --- |
| Full | Docs complete, adapter/UI can honor the surface, ID is live | `isFullySupported: true`; `isSeeded: true` only if it belongs on a first-launch picker |
| Catalog | ID should be recognized on fetch/Add Model, but some surface is unverified or the adapter cannot send it | `isFullySupported: false` or omit the unverified capability; usually `isSeeded: false` |
| Skip | No official ID, announcement-only, or wrong product surface (ChatGPT UI name, batch-only, etc.) | no record |

`isSeeded` affects **first launch** via `DefaultProviderSeeds` → `ModelCatalog.seededModels`. Existing installs pick up catalog metadata when they Add/Refresh that exact ID, or via `ModelSettingsResolver` catalog fallback for a persisted ID. Do not seed retired, invitation-only, or niche preview IDs.

`claudeManagedAgents` reuses `anthropicRecords`. `openaiWebSocket` mirrors OpenAI records but `isFullySupported` is forced off unless the record has `.streaming` or `.imageGeneration`.

### 5. Implement — layer order

Do not stop after the catalog row. Walk [references/layers.md](references/layers.md) top to bottom.

Minimum for a chat model:

1. `ModelCatalog` record in the correct `ModelCatalogRecords+*.swift` (exact ID, display name, capabilities, context, max output, reasoningConfig, flags). Comment the source + date.
2. `ModelCapabilityRegistry` exact-ID sets: effort band, default effort, max/xhigh, verbosity/pro/context, web search, code execution, Google Search/Maps as applicable.
3. `ModelSettingsResolver` always-on lists if Off is illegal.
4. Provider-specific support files (`AnthropicModelLimits`, `GeminiModelConstants`, `XAIModelSupport`, `OpenAIImageModelSupport`, `OpenCodeGoAdapter` routing sets, sampling gates in `AdapterModelCapabilities`, …).
5. Adapter `*+ModelCatalog.swift` / `*RequestSupport.swift` so fetch and request bodies honor the new ID (no 400 from extra fields, no silent drop of video/PDF).
6. UI: `ChatViewModelIDs`, `ChatModelSelectionSupport` preferred orders, `ChatAttachmentCapabilitySupport`, composer controls. Update copy if a control appears/disappears.
7. Tests — [references/tests.md](references/tests.md).

Gateway mirrors are **separate records** with **that gateway's slug**:

- Cloudflare: `openai/gpt-5.2`, `anthropic/claude-opus-5`, `google-ai-studio/gemini-3.7-flash`
- Vercel: `openai/…`, `anthropic/claude-sonnet-4.6` (dots vs dashes differ from Anthropic native), `google/…`, `xai/grok-4.6`
- OpenRouter: `openai/…`, `anthropic/…`, `x-ai/grok-4.6`, `google/gemini-3.7-flash`
- Fireworks: seed `accounts/fireworks/models/…` and add the `fireworks/…` alias as a second exact record
- OpenCode Go: bare IDs + **exact** endpoint routing sets (`anthropicMessagesModelIDs` / `openAIResponsesModelIDs`)

Do not enable `.nativePDF` on Cloudflare or Vercel by default.

### 6. Tests and verify

Add or extend:

- Exact-ID catalog values (context, max output, capabilities, reasoning)
- Similar-ID conservative fallback (`id-custom` is unknown)
- Fully-supported exact match true, sibling false
- Resolver catalog fallback for a **stale persisted** `ModelInfo` (old capabilities/context, no overrides)
- Effort band / web search / code execution / sampling / PDF / videoInput as touched
- Adapter request tests if the wire body changed

```bash
swift test --filter ModelCatalogTests
swift test --filter JinModelSupportTests
swift test --filter ModelCapabilityRegistryTests
swift test --filter ModelSettingsResolverTests
```

Plus the provider-specific suite you touched. Then `swift test` if the change is wide.

After code changes: `bash Packaging/package.sh` once (repo rule). Docs-only skill edits do not need packaging.

### 7. Stop conditions

Stop and report instead of shipping guesses when:

- Official pages disagree and you cannot tell which is current
- The API ID is not published
- A parameter exists on one provider copy and is undocumented on another
- Video input is requested but no live probe was done
- Marking fully-supported would show a control that 400s

## Done when

- Evidence sheet cites official URLs + date for every non-conservative field
- Catalog ID is exact; `id-custom` stays conservative
- Every touched allowlist / UI set / adapter gate uses that same exact ID
- Tests cover catalog, fallback, fully-supported, and resolver legacy
- Composer/settings would show the right controls and would not send rejected params
- Unverified fields are conservative and commented

## Do not

- Broaden `hasPrefix` / `contains` to classify a new family
- Copy OpenRouter/Cloudflare/Vercel capabilities from the native catalog
- Set `.videoInput` because a card lists `video`
- Seed invitation-only or shut-down IDs
- Add a catalog row without registry/UI/adapter follow-through “to finish later”
- Trust ChatGPT / Claude.ai / Gemini app names as API IDs
- Log API keys or live `/models` payloads that contain secrets
