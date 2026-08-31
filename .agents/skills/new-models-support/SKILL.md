---
name: new-models-support
description: "Discover newly released LLM, image, and video models from official provider docs and add complete Jin support (catalog, exact-ID capabilities, adapters, UI controls, tests). Use when adding or updating a model ID, scanning for latest models, fixing model metadata, or when the user says support this model."
---

# New Models Support

Find newly released models (default window: last 7 days) from **official provider docs** and add complete Jin support: catalog, exact-ID capabilities, adapters, UI controls, tests.

This skill is a census, not a highlights reel. **Every first-class provider must be searched and fetched.** Sampling “the big labs” and waving at the rest is a failed run.

## Hard rules (do not skip)

1. **Enumerate providers from code, not memory.** Read `Sources/Domain/ProviderTypes.swift` (`ProviderType` cases) and `Sources/Domain/DefaultProviderSeeds.swift`. The work list is every first-class provider except the generic `.openaiCompatible` catch-all (still note it as out of scope). `claudeManagedAgents` shares Anthropic model IDs but still needs its own docs/catalog check.
2. **One provider = one official search + one official fetch, minimum.** For each provider you MUST:
   - `web_search` with that provider’s name + “models” / “changelog” / “API” and the date window
   - `web_fetch` the official models page **and** changelog/release-notes page when they exist
   - Diff live IDs against `ModelCatalog.orderedRecords` / the provider’s `*Records` file
3. **Do not implement until the census table is complete.** No catalog edits while any provider row is blank, “later”, “probably nothing”, or inferred from another provider.
4. **Hosted copies are not optional.** If origin shipped a new ID this window, check **every gateway** (Fireworks, Together, DeepInfra, Baseten, Groq, Cerebras, SambaNova, Modal, Makora, RunInfra, OpenCode Go, OpenRouter, Vercel AI Gateway, Cloudflare AI Gateway, Ramp Router, Databricks) for that **exact** hosted ID. Origin already being in Jin does not mean RunInfra/Fireworks/Vercel were updated.
5. **Exact IDs only.** Follow repo `AGENTS.md` model rules: no prefix/substring expansion, no family-level guesses, no copying OpenRouter limits onto another gateway. Uncertain → conservative + mark follow-up.
6. **A 403/404/503/empty SPA is not a pass.** Retry the docs index (`llms.txt`), changelog, library slug, and `GET /v1/models` docs. If still blocked, the row is `blocked` with the URLs tried — never `done`.
7. **Incomplete adapter ≠ skip the ID.** If the official ID is new but Jin cannot fully wire it (video/image/STT surface missing), record it as `blocked-adapter` with the exact ID. Do not pretend the provider was “processed” with no finding.

## Required census table (paste in the working notes before any code change)

Fill **every** row. Status must be one of: `no-new` | `added` | `already-cataloged` | `blocked` | `blocked-adapter`.

| Provider | Official models URL fetched | Changelog/library URL fetched | New exact IDs this window | Status |
|---|---|---|---|---|
| OpenAI | | | | |
| OpenAI (WebSocket) | | | | |
| GitHub Copilot | | | | |
| Groq | | | | |
| OpenRouter | | | | |
| Cloudflare AI Gateway | | | | |
| Vercel AI Gateway | | | | |
| Anthropic | | | | |
| Claude Managed Agents | | | | |
| Cohere | | | | |
| Mistral | | | | |
| Perplexity | | | | |
| DeepInfra | | | | |
| Together AI | | | | |
| Baseten | | | | |
| RunInfra | | | | |
| xAI | | | | |
| DeepSeek | | | | |
| Zhipu Coding Plan | | | | |
| MiniMax | | | | |
| MiniMax Token Plan | | | | |
| Xiaomi MiMo Token Plan (OpenAI) | | | | |
| Xiaomi MiMo Token Plan (Anthropic) | | | | |
| Kimi for Coding | | | | |
| Fireworks | | | | |
| Cerebras | | | | |
| SambaNova | | | | |
| Databricks | | | | |
| Modal | | | | |
| Makora | | | | |
| MorphLLM | | | | |
| OpenCode Go | | | | |
| Ramp Router | | | | |
| Gemini (AI Studio) | | | | |
| Vertex AI | | | | |
| Zyphra | | | | |
| Meta | | | | |

Starting official URLs (fetch these; search is still required because slugs move):

- OpenAI: `https://developers.openai.com/api/docs/models`
- Anthropic: `https://platform.claude.com/docs/en/about-claude/models/overview`
- Gemini: `https://ai.google.dev/gemini-api/docs/models` + `https://ai.google.dev/gemini-api/docs/changelog`
- Vertex AI: `https://docs.cloud.google.com/vertex-ai/generative-ai/docs/learn/models`
- Groq: `https://console.groq.com/docs/models`
- Fireworks: `https://fireworks.ai/models`
- Together: `https://docs.together.ai/docs/serverless-models`
- DeepSeek: `https://api-docs.deepseek.com/quick_start/pricing`
- MiniMax: `https://platform.minimax.io/docs/api-reference/api-overview`
- Z.AI / Zhipu: `https://docs.z.ai/release-notes/new-released`
- OpenCode Go: `https://opencode.ai/docs/go`
- xAI: `https://docs.x.ai/developers/models`
- OpenRouter: `https://openrouter.ai/models`
- Vercel AI Gateway: `https://vercel.com/ai-gateway/models`
- Mistral: `https://docs.mistral.ai/getting-started/changelog`
- Cohere: `https://docs.cohere.com/docs/models`
- RunInfra: `https://runinfra.ai/docs/introduction/quickstart.md` + `https://runinfra.ai/inference-api` + `https://runinfra.ai/docs/api-reference/chat-completions.md`
- Meta: `https://dev.meta.ai/docs/models`
- Kimi: `https://platform.kimi.ai/docs/models`
- Cerebras: `https://inference-docs.cerebras.ai/models/overview`
- Databricks: `https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis/supported-models`

If `ProviderType` gained a case not in this table, add the row. Do not drop rows.

## Implementation (only after the table is full)

Sync every affected layer together, per `AGENTS.md`:

- provider seeds
- adapter model metadata
- Add Model inference
- settings resolver (including legacy persisted-model fallback)
- fully-supported allowlists
- capability UI (reasoning, web search, vision, video, image)
- regression tests for the exact IDs (context window, capabilities, legacy rows)

Do not mark a gateway copy fully supported unless that gateway’s own docs/live `/models` publish **that exact ID** and the adapter can send it.

After code changes: `bash Packaging/package.sh` once (not for docs-only).

## Done criteria

- Census table has a non-empty official URL and a status for **every** provider row
- New IDs are implemented or explicitly `blocked` / `blocked-adapter` with the reason
- Tests cover added exact IDs
- You can point to the search/fetch evidence for RunInfra, Fireworks, OpenCode Go, and every other gateway — not just OpenAI/Anthropic/Gemini
