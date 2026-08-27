# Official sources and ID conventions

Always re-search. These URLs rot. Prefer the vendor's current "models" index, then the **per-model** page for the exact ID.

`models.dev` is a discovery hint, not evidence. OpenRouter `/models` is evidence **only** for OpenRouter slugs and OpenRouter-reported effort bands — not for native OpenAI/Anthropic/Gemini capabilities.

## First-party

### OpenAI (`openai`, `openaiWebSocket`)

- Index: `https://platform.openai.com/docs/models`
- API: `https://platform.openai.com/docs/api-reference`
- IDs: bare (`gpt-5.6-sol`, `gpt-5.4-2026-03-05`). Dated snapshots are **separate** exact IDs.
- Request shape: Responses API (chat/completions is not the Jin path for first-party OpenAI).
- Watch: reasoning effort (`none`…`max`; some families dropped `minimal` and added `max`), `reasoning.mode=pro`, `reasoning.context`, `text.verbosity`, code interpreter allowlist, native PDF (not every `gpt-5*`), sampling (many GPT-5 reject `temperature`/`top_p` unless reasoning is off — and only some IDs even then).
- Image: `OpenAIImageModelSupport` families (`gpt-image-*`, `dall-e-*`) — different size/quality/edit rules per ID.
- WebSocket: same catalog; fully-supported only if `.streaming` or `.imageGeneration`.

### Anthropic (`anthropic`, `claudeManagedAgents`)

- Index: `https://docs.anthropic.com/en/docs/about-claude/models`
- IDs: `claude-opus-5`, `claude-sonnet-4-6`, `claude-fable-5`. Date suffixes are extra IDs.
- Watch: adaptive thinking vs `budget_tokens`; whether omitting `thinking` disables or enables; whether `{type:"disabled"}` is legal; effort ladder (`low`…`max` vs no `xhigh`); fast mode **exact IDs only**; sampling stripped on current adaptive models; 1M context vs output cap; code execution and web search tool versions (`web_search_20260209` dynamic filtering is a separate exact list).
- Managed agents reuse Anthropic records but **web search and code execution are off** in the registry for `.claudeManagedAgents`.

### Google Gemini API (`gemini`) and Vertex AI (`vertexai`)

- Gemini API: `https://ai.google.dev/gemini-api/docs/models`
- Vertex: `https://cloud.google.com/vertex-ai/generative-ai/docs/models`
- IDs: `gemini-3.7-flash`, `gemini-3.1-pro-preview`, `veo-3.1-generate-preview`. Preview vs GA vs `-001` retired IDs differ.
- Watch: `thinking_level` bands are **per ID** (3.7 Flash rejects `MINIMAL`; 3 Pro is often LOW/HIGH only). Sampling deprecated on some Flash IDs. Google Search vs Maps allowlists differ between Gemini API and Vertex. Image models (`*-image`) and Veo are not chat. Native PDF sendability is adapter-gated (`GeminiModelConstants.supportsNativePDF` vs Vertex).
- `.videoInput`: Google text models on `generateContent` take `inlineData`. Image/Veo records must **not** claim it.

### xAI (`xai`)

- `https://docs.x.ai/docs/models` and `https://docs.x.ai/developers/models`
- IDs: `grok-4.6`, `grok-imagine-video-1.5`. Multi-agent IDs are separate.
- Watch: “Reasoning cannot be disabled” on some Grok IDs; effort vs agent-count labels; image-to-video-only IDs that 400 on text-to-video; 1080p only on listed video IDs; web search off for media-generation IDs.

### DeepSeek (`deepseek`)

- `https://api-docs.deepseek.com`
- IDs and thinking/`reasoning_effort` bands are version-specific (V4 Pro vs Flash).

### Mistral (`mistral`)

- `https://docs.mistral.ai/getting-started/models/`
- Exact IDs like `mistral-medium-3.5`. Some reasoning models are high-only.

### Moonshot / Kimi (`kimiForCoding` and hosted copies)

- Kimi Code: `https://kimi.com/code/docs` (or current official coding-plan docs)
- Hosted IDs differ: `kimi-k3`, `moonshotai/Kimi-K3`, `moonshotai/kimi-k3`, `accounts/fireworks/models/kimi-k3`.
- Watch: thinking always-on vs toggle; temperature fixed at 1.0 on several Kimi IDs.

### Zhipu / Z.AI (`zhipuCodingPlan` and hosted copies)

- `https://docs.z.ai` / `https://docs.bigmodel.cn`
- IDs: `glm-5.3`, `glm-5.3[1m]`, `glm-5.3-flash` — brackets are part of the ID.
- Watch: `thinking.type: disabled` often illegal (always-on; disable maps to `low`).

### MiniMax (`minimax`, `minimaxCodingPlan`)

- Official MiniMax API docs. Token-plan IDs can differ from the public API.

### Meta (`meta`)

- `https://dev.meta.ai/docs/models`
- Muse Spark IDs: `muse-spark-1.2`, `muse-spark-1.2-contributor`. Thinking cannot be disabled; `none` 400s.

### Perplexity (`perplexity`)

- `https://docs.perplexity.ai`
- Search is inherent. Native PDF upload is **not** supported (files text-fallback).

## Gateways and hosts

Each host's slug is a new exact ID. Confirm against **that** host's model page or `GET /models`.

| Provider | Docs / catalog | ID shape |
| --- | --- | --- |
| OpenRouter | `https://openrouter.ai/models` + `GET /api/v1/models` | `vendor/slug`, optional `:free` |
| Cloudflare AI Gateway | Cloudflare AI Gateway model docs + compat `/models` | fully-qualified `openai/gpt-5.2`, `google-ai-studio/…`, `google-vertex-ai/google/…` |
| Vercel AI Gateway | `https://ai-gateway.vercel.sh/v1/models` | `openai/…`, `anthropic/claude-sonnet-4.6` (dots), `google/…`, `xai/…`, `zai/…` |
| Together | `https://docs.together.ai` + model pages | `org/name` |
| Fireworks | `https://fireworks.ai/models` | `accounts/fireworks/models/…` and `fireworks/…` aliases; routers `accounts/fireworks/routers/…` |
| Groq | `https://console.groq.com/docs/models` | bare or org-prefixed as published |
| Cerebras | Cerebras inference docs | as published |
| SambaNova | SambaNova docs | exact, no substring |
| DeepInfra | DeepInfra model pages | `org/Name` (capitalization still stored as published; lookup is case-insensitive) |
| Baseten | `https://docs.baseten.co/inference/model-apis/overview` | Model APIs IDs from live `/v1/models` |
| Modal | Modal docs + Auto Endpoints | HF-style `org/name`; request host may live in `catalogMetadata.requestBaseURL` |
| Makora | Makora provider docs | org/name |
| MorphLLM | Morph docs | as published |
| Databricks | Databricks model serving | gateway-specific; Anthropic path uses curated Claude set |
| Ramp Router | **live** `GET https://api.router.com/v1/models` only | bare public names; effort band is enforced |
| RunInfra | `https://runinfra.ai/docs` + library | as published |
| OpenCode Go | `https://opencode.ai/docs/go/` + `GET /zen/go/v1/models` | bare IDs; endpoint table is per ID |
| Zyphra | Zyphra docs | as published |
| GitHub Copilot | GitHub Models catalog | fetch-derived; catalog entries override when present |
| Xiaomi MiMo token plans | MiMo docs + `MiMoModelIDs` | OpenAI vs Anthropic plan IDs differ |

### Gateway rules

- **Native PDF off** on Cloudflare and Vercel unless Jin grows a real PDF translator for that gateway.
- **Code execution / Maps / OpenAI verbosity / pro mode** usually native-only. Do not enable because the native twin has them.
- OpenRouter web plugin (`plugins: [{id:"web"}]`) has its **own** allowlist, not the Gemini one.
- Vercel `xai/grok-4.6` ≠ OpenRouter `x-ai/grok-4.6` ≠ native `grok-4.6`.
- Anthropic on Vercel often uses **dots** (`claude-opus-4.8`); native Anthropic uses **dashes** (`claude-opus-4-8`). Both are exact IDs on their provider.

## Router special case

`ModelCatalogRecords+Router.swift` is sourced from live `/v1/models` (`reasoning.supported_efforts`, `default_effort`). Do **not** copy `docs.router.com/supported-models`. Out-of-band effort → `400 Invalid reasoning effort.`

## OpenCode Go special case

Routing is the support. Adding a catalog row without updating `OpenCodeGoAdapter.anthropicMessagesModelIDs` / `openAIResponsesModelIDs` / temperature lock sets will send the wrong payload.

Video input: only IDs that (a) live on `/chat/completions` or a video-capable Responses path **and** (b) passed a live colour-clip probe. `/messages` has no video block.

## Discovery order for an undirected scan

1. OpenAI, Anthropic, Gemini/Vertex, xAI
2. DeepSeek, Mistral, Kimi, Zhipu, MiniMax, Meta
3. Hosted copies of anything new in (1)–(2): OpenRouter, Cloudflare, Vercel, Together, Fireworks, Groq, OpenCode Go, Baseten, DeepInfra, Modal, Router, RunInfra

Do not bulk-add every OpenRouter listing. Add hosted copies when the native model is fully evidenced **and** that host publishes a live slug.
