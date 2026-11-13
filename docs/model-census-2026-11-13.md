# Model Census — 2026-11-13

Window: 2026-11-06 → 2026-11-13 (today). Follows `model-census-2026-11-10.md`
(window 11-03 → 11-10). Provider list enumerated from
`Sources/Domain/ProviderTypes.swift` (36 cases) + `DefaultProviderSeeds.swift`.
`.openaiCompatible` is the generic catch-all — out of scope per skill rules.

Evidence: official docs pages + changelogs fetched for every row; live
`/models` JSON feeds diffed against `ModelCatalog.orderedRecords` for
OpenRouter, Vercel AI Gateway, DeepInfra, OpenCode Go, Zyphra, Fireworks,
MorphLLM, Makora (status page), Cloudflare model catalog.

| Provider | Official models URL fetched | Changelog/library URL fetched | New exact IDs this window | Status |
|---|---|---|---|---|
| OpenAI | developers.openai.com/api/docs/models | developers.openai.com/api/docs/changelog | none new (gpt-image-2.5, gpt-6.1-* already cataloged; `gpt-6-cyber` still lacks documented reasoning controls/Daybreak defaults → stays blocked) | blocked (gpt-6-cyber carried) |
| OpenAI (WebSocket) | same as OpenAI | same | same — shares OpenAI catalog | blocked (gpt-6-cyber carried) |
| GitHub Copilot | docs.github.com/en/copilot/reference/ai-models/supported-models | github.blog/changelog | page is auth-gated SPA; no verifiable new IDs | blocked |
| Groq | console.groq.com/docs/models | console.groq.com/docs/changelog | none (`qwen/qwen3.8-27b` preview already cataloged) | no-new |
| OpenRouter | openrouter.ai/api/v1/models (live) | openrouter.ai/blog | `google/gemini-4-carbon`, `google/gemini-4-hydrogen`, `baidu/ernie-5.5-flash-preview:free`, `baidu/ernie-light-dt-1.0-intl`, `nex-agi/nex-n2.6`, `thinkingmachines/inkling-2-small`; `:batch` variants expose only `/api/v1/batches` → blocked-adapter | added + blocked-adapter (:batch) |
| Cloudflare AI Gateway | developers.cloudflare.com/ai/models | developers.cloudflare.com/llms.txt | `anthropic/claude-fable-5.2`, `google/gemini-4-carbon`, `@cf/thinkingmachines/inkling-2-small`; `meta/muse-ember-1.0` still publishes no context window → stays blocked; `openai/decisions` → blocked-adapter | added + blocked |
| Vercel AI Gateway | ai-gateway.vercel.sh/v1/models (live) | vercel.com/changelog | `google/gemini-4-carbon`, `google/gemini-4-hydrogen`, `thinkingmachines/inkling-2-small`, `paperinstruments/ultramarine-1-flash`; `google/gemini-decision-1`, `perplexity/pplx-decider-v1.3`, `perplexity/pplx-decider-flash-v1.3` (type `evaluation`), `minimax/minimax-h3-image`, `minimax/minimax-h3-image-highspeed` (type `image`) → blocked-adapter | added + blocked-adapter |
| Anthropic | platform.claude.com/docs/en/models/overview | platform.claude.com/docs/en/release-notes/overview | none — `claude-fable-5-2` + `claude-mythos-5-2` (Nov 9) already cataloged | already-cataloged |
| Claude Managed Agents | platform.claude.com/docs (same Anthropic IDs) | same | shares Anthropic catalog — nothing new | already-cataloged |
| Cohere | docs.cohere.com/docs/models | docs.cohere.com/v2/changelog | none in window | no-new |
| Mistral | docs.mistral.ai (models) | docs.mistral.ai/resources/release-notes | none in window | no-new |
| Perplexity | docs.perplexity.ai/docs/agent-api/models | docs.perplexity.ai/docs/resources/changelog | Agent API added `anthropic/claude-fable-5-2`, `google/gemini-4-carbon` + `ultra` effort (Nov 5/11) — Jin's perplexity provider wires the sonar chat API only; Agent API is a different surface → blocked-adapter | blocked-adapter |
| DeepInfra | api.deepinfra.com/models/list (live) | deepinfra.com/blog | `Lightricks/LTX-Upscale`, `LTX-2.5-Fast`, `LTX-2.3-Fast`, `LTX-HDR`, `LTX-2.3-Pro`, `LTX-AlphaGen`, `LTX-Reframe`, `LTX-2.5-Pro` (text-to-video), `nace-ai/drex-max-finance` (decision) — no chat model | blocked-adapter |
| Together AI | docs.together.ai/docs/serverless-models | docs.together.ai/docs/serverless-models | `thinkingmachines/Inkling-2-Small` (1,048,576 ctx, native image input, variable effort; max output unpublished) | added |
| Baseten | docs.baseten.co/inference/model-apis/overview | docs.baseten.co/_llms/documentation.txt | supported-models table is client-rendered (empty tbody in markdown); `/v1/model_apis` needs a key → cannot verify exact IDs | blocked |
| RunInfra | runinfra.ai/docs/api-reference/models | runinfra.ai/docs/changelog | none — Step 5 Preview (Nov 6) + Nov 10 param changes already covered | no-new |
| xAI | docs.x.ai/developers/models | docs.x.ai/developers/release-notes | `grok-4.7` already cataloged; `grok-voice-transcribe-2.0` is STT — no STT surface (already documented as deliberately uncataloged) | already-cataloged |
| DeepSeek | api-docs.deepseek.com/quick_start/pricing | api-docs.deepseek.com | `deepseek-flash` already cataloged; no new chat IDs | no-new |
| Zhipu Coding Plan | docs.z.ai/devpack/overview | docs.z.ai/release-notes/new-released | none in window | no-new |
| MiniMax | platform.minimax.io/docs/api-reference/api-overview | platform.minimax.io release notes | `MiniMax H3 Image` + `-Highspeed` (Nov 10) are image-generation models; minimax adapter is chat-only → blocked-adapter | blocked-adapter |
| MiniMax Token Plan | same MiniMax docs | same | same H3 Image finding | blocked-adapter |
| Xiaomi MiMo Token Plan (OpenAI) | mimo.mi.com docs | mimo.mi.com/static/docs/updates/model | no November entries | no-new |
| Xiaomi MiMo Token Plan (Anthropic) | same | same | same | no-new |
| Kimi for Coding | kimi.com/code/docs models | kimi.com/code/docs whats-new | client releases only (v1.3.4/v2.6.0); six model IDs unchanged (`k3.1-pro`, `k3.1-pro-highspeed`, `k3`, `k3-256k`, `k2.8-preview`, `k2.7-code-highspeed`) | already-cataloged |
| Fireworks | fireworks.ai/models (library pages) | fireworks.ai library | `accounts/fireworks/models/kimi-k3p1-pro` (created 2026-11-02 on page; 1M ctx, text+image, function calling, cached-input pricing) | added |
| Cerebras | inference-docs.cerebras.ai/models/overview | inference-docs.cerebras.ai/support/change-log | Nov 9 changelog adds Kimi K3.1 Pro to the **Dedicated** catalog — Jin's cerebras provider is Shared Inference only → blocked-adapter | blocked-adapter |
| SambaNova | docs.sambanova.ai models page | docs.sambanova.ai release-notes | release notes last updated July; `MiniMax-M3.1-Flash` sits in Preview (undated, model itself is Oct 19) → no in-window release | no-new |
| Databricks | docs.databricks.com .../supported-models (updated 2026-11-10) | same | `databricks-gemini-4-carbon`, `databricks-claude-fable-5-2`. `gemini-4-hydrogen` GA'd Nov 12 on Vertex but is NOT yet on the Databricks page → not added | added |
| Modal | modal.com/docs/guide/supported-models | modal.com/changelog | Kimi K3.1 Pro Shared Endpoint announced Nov 4 (just outside window, uncataloged) → `moonshotai/Kimi-K3.1-Pro` added | added |
| Makora | status.makora.com | makora.com/blog | status page lists operational models with no release dates; blog has no November model posts → cannot verify a new ID | blocked |
| MorphLLM | morphllm.com live model feed | morphllm.com/blog | feed lists `morph-glm52-744b`, `morph-dsv41flash-abliterated` (uncataloged) but feed has no timestamps; Nov 11 blog is "Capy on Morph Ultra" (no new model ID) | blocked |
| OpenCode Go | opencode.ai/docs/go + live model feed | opencode.ai/console/changelog | live feed renamed `longcat-2.5-preview-free` → `longcat-2.5-free` (release_date 2026-11-02, 1M ctx / 262,144 output, text+image, tools, reasoning toggle) | added |
| Ramp Router | docs.router.com/supported-models | docs.router.com | docs warn display labels are not callable IDs; `GET /v1/models` is authoritative and needs a key → cannot verify `kimi-k3.1-pro` callable ID | blocked |
| Gemini (AI Studio) | ai.google.dev/gemini-api/docs/models | ai.google.dev/gemini-api/docs/changelog | `gemini-4-carbon` (GA Nov 10), `gemini-4-hydrogen` (GA Nov 12); `gemini-decision-1` (Decisions API, zero output tokens) → blocked-adapter; `gemini-omni-1.2-flash` needs the Omni video surface → blocked-adapter | added + blocked-adapter |
| Vertex AI | docs.cloud.google.com/vertex-ai/generative-ai/docs/learn/models | docs.cloud.google.com/gemini-enterprise-agent-platform/release-notes | `gemini-4-carbon` + `gemini-4-carbon-cyber-permissive` (GA Nov 10), `gemini-4-hydrogen` (GA Nov 12); `claude-fable-5-2` + `meta/muse-*` partner routes need Anthropic Messages / Meta Responses surfaces the Vertex adapter lacks → blocked-adapter (carried) | added + blocked-adapter |
| Zyphra | zyphra feed (api.zyphra.com models) | zyphra.com | `zai-org/GLM-5.3-Flash-FP4` (releaseDate 2026-11-12, 1,048,576 / 131,072, text+image, function calling); `zyphra/ZONOS3-Mini` (2026-11-09) is TTS → blocked-adapter | added + blocked-adapter |
| Meta | dev.meta.ai/docs/models | dev.meta.ai/docs/muse-code/changelog | changelog is client-release notes only; no new model IDs | no-new |

## Gateway cross-check for origin releases

- Gemini 4 Carbon / Hydrogen (origin Nov 10 / Nov 12): present on OpenRouter
  (+`:batch`), Vercel, Cloudflare (`google/gemini-4-carbon` only — no hydrogen
  or AI-Studio/Vertex compound copies listed yet), Databricks (carbon only).
  Not present on Fireworks/Together/DeepInfra/Baseten/Groq/Cerebras/SambaNova/
  Modal/Makora/RunInfra/OpenCode Go/Ramp Router live inventories checked.
- Claude Fable 5.2 (origin Nov 9, covered last census): hosted copies now also
  on Cloudflare (`anthropic/claude-fable-5.2`) and Databricks
  (`databricks-claude-fable-5-2`, catalog-only — messages route unsupported).
  Perplexity Agent API copy → blocked-adapter (different API surface).
- Inkling 2 Small (origin ~Nov 10): hosted on OpenRouter (paid + `:free`),
  Vercel, Cloudflare Workers AI (`@cf/thinkingmachines/inkling-2-small`),
  Together (`thinkingmachines/Inkling-2-Small`).
- Kimi K3.1 Pro (origin Oct): newly hosted on Modal (Nov 4), Fireworks
  (`kimi-k3p1-pro`), Cerebras Dedicated (blocked-adapter), already on
  OpenCode Go / OpenRouter / Vercel / Databricks / Baseten catalog.

## Blocked / blocked-adapter ledger

- `gpt-6-cyber` (OpenAI + WebSocket): reasoning controls & Daybreak defaults
  undocumented — carried from 11-10 census.
- GitHub Copilot Claude Fable 5.2: only display name verified — carried.
- `meta/muse-ember-1.0` (Cloudflare): no context window published — carried.
- OpenRouter `*:batch` copies of gemini-4-carbon/hydrogen/claude-fable-5.2:
  batch-only endpoint surface.
- Vercel `google/gemini-decision-1`, `perplexity/pplx-decider-v1.3`,
  `perplexity/pplx-decider-flash-v1.3`: `evaluation` type, no text generation.
- Vercel `minimax/minimax-h3-image{,-highspeed}`: `image` type; Vercel
  adapter has no image-generation surface.
- Cloudflare `openai/decisions`, Gemini `gemini-decision-1`, DeepInfra
  `nace-ai/drex-max-finance`: decision/evaluation models, no chat surface.
- DeepInfra 8× LTX video models: no video-generation surface on deepinfra.
- Cerebras Kimi K3.1 Pro: Dedicated catalog only; Jin uses Shared Inference.
- Perplexity Agent API models: separate API surface from sonar chat.
- MiniMax H3 Image (+Highspeed): image generation; chat-only adapter.
- Vertex `claude-fable-5-2`, `meta/muse-wonder-1.0`, `meta/muse-ember-1.0`,
  `meta/muse-spark-1.3`: partner routes need Messages/Responses APIs.
- Zyphra `zyphra/ZONOS3-Mini`: TTS; no audio-generation surface.
- Gemini `gemini-omni-1.2-flash` / `gemini-omni-1.1-flash`: Omni video
  generation surface (carried).
- Ramp Router: live `/v1/models` requires auth — new hosted copies
  unverifiable this window.
- Baseten, Makora, MorphLLM, GitHub Copilot: official model lists blocked or
  undated (see table).
