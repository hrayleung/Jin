# Gemma 4 provider support review (2026-04-04)

This note captures the public evidence reviewed for Google Gemma 4 support across Jin provider surfaces on 2026-04-04.

## Summary

Only the following Jin provider surfaces have strong, exact-ID public evidence that is precise enough for Jin's fully-supported exact-match catalog entries:

- **Gemini (AI Studio)** for `gemma-4-31b-it`
- **Vercel AI Gateway**
- **OpenRouter**

Google's launch post confirms **Google AI Studio** access to Gemma 4 (31B and 26B MoE), and Google's Gemini API page shows the exact runtime ID `gemma-4-31b-it`. This review still did **not** find equally strong public exact-ID evidence for Vertex AI or Cloudflare AI Gateway runtime IDs, so those should remain conservative/unconfirmed.

## Provider matrix

| Provider surface in Jin | Status from this review | Exact public IDs confirmed | Notes |
| --- | --- | --- | --- |
| Gemini (AI Studio) | **Confirmed for conservative exact-ID Jin catalog support** | `gemma-4-31b-it` | Google's Gemini API page shows the exact runtime ID in both SDK and REST examples. Reviewed evidence is strong for 31B only. |
| Vertex AI | **Unconfirmed for exact-ID Jin catalog support** | None found in reviewed sources | Google launch post mentions customization on Vertex AI, not hosted inference IDs/capabilities suitable for exact Jin entries. |
| OpenRouter | **Confirmed** | `google/gemma-4-31b-it`, `google/gemma-4-26b-a4b-it` | Public OpenRouter model pages expose exact IDs and model capabilities. |
| Vercel AI Gateway | **Confirmed** | `google/gemma-4-31b-it`, `google/gemma-4-26b-a4b-it` | Vercel changelog and model pages expose exact IDs plus context/max-output metadata. |
| Cloudflare AI Gateway | **Unconfirmed** | None found in reviewed sources | No reviewed public Cloudflare model page/docs evidence for Gemma 4 exact IDs. |
| DeepInfra | **Unconfirmed** | None found in reviewed sources | No reviewed public DeepInfra Gemma 4 listing. |
| Together AI | **Unconfirmed** | None found in reviewed sources | No reviewed public Together Gemma 4 listing. |
| Fireworks | **Unconfirmed** | None found in reviewed sources | No reviewed public Fireworks Gemma 4 listing. |
| Groq | **Unconfirmed** | None found in reviewed sources | No reviewed public Groq Gemma 4 listing. |

## Public evidence reviewed

### Google / Gemma 4 launch

- Google launch post: https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/
- Gemini API page: https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api
- Key point for Jin review: Google says developers can explore Gemma 4 in **Google AI Studio** (31B and 26B MoE), and customize Gemma 4 using platforms like **Vertex AI**.
- The Gemini API page includes both SDK and REST examples using the exact runtime ID `gemma-4-31b-it`, which is strong enough for a conservative exact-ID Jin catalog entry for the Gemini provider.
- Review interpretation: Gemini API has strong exact-ID evidence for `gemma-4-31b-it`; Vertex AI still lacks equally strong public exact-ID runtime evidence in the reviewed sources.

### Vercel AI Gateway

- Changelog: https://vercel.com/changelog/gemma-4-on-ai-gateway
- Model page (31B): https://vercel.com/ai-gateway/models/gemma-4-31b-it
- Model page (26B A4B): https://vercel.com/ai-gateway/models/gemma-4-26b-a4b-it
- Public evidence from reviewed pages:
  - Vercel states Gemma 4 26B and 31B are available on AI Gateway.
  - Vercel gives exact IDs: `google/gemma-4-31b-it` and `google/gemma-4-26b-a4b-it`.
  - Vercel documents function-calling/tool use, reasoning, native vision, and file input.
  - Vercel model pages expose **262K context** and **131K max output** for both models.

### OpenRouter

- 31B page: https://openrouter.ai/google/gemma-4-31b-it
- 26B A4B page: https://openrouter.ai/google/gemma-4-26b-a4b-it
- Public evidence from reviewed pages:
- OpenRouter exposes exact IDs `google/gemma-4-31b-it` and `google/gemma-4-26b-a4b-it`.
- Both pages expose **262,144 context**.
- OpenRouter documents reasoning support and native function calling.
- 31B page documents text + image input with text output.
- 26B page documents multimodal input including text, images, and video; for Jin catalog purposes this still maps conservatively to the existing **vision** capability rather than a new video-generation capability.
- OpenRouter's public models API also exposes exact completion ceilings used here: `131,072` for `google/gemma-4-31b-it` and `262,144` for `google/gemma-4-26b-a4b-it`.

## Conservative Jin metadata recommendation

For **confirmed** providers only:

### Gemini (AI Studio)

Recommended exact-ID entry:

- `gemma-4-31b-it`

Recommended conservative metadata:

- capabilities: `.streaming`, `.toolCalling`, `.vision`, `.reasoning`
- context window: `262_144`
- max output tokens: leave unset unless Google publishes an exact limit for this Gemini API surface
- `reasoningConfig`: `.effort` with a conservative default like `.medium`
- `isFullySupported: true`
- keep `audio`, `promptCaching`, `nativePDF`, `codeExecution`, `googleSearch`, and `googleMaps` **off** unless separately documented for this exact model ID

### Vercel AI Gateway

Recommended exact-ID entries:

- `google/gemma-4-31b-it`
- `google/gemma-4-26b-a4b-it`

Recommended conservative metadata:

- capabilities: `.streaming`, `.toolCalling`, `.vision`, `.reasoning`
- context window: `262_144`
- max output tokens: `131_072`
- `reasoningConfig`: `.effort` with a conservative default like `.medium`
- `isFullySupported: true`
- keep `promptCaching`, `nativePDF`, `codeExecution`, `googleSearch`, and `googleMaps` **off** unless separately documented

### OpenRouter

Recommended exact-ID entries:

- `google/gemma-4-31b-it`
- `google/gemma-4-26b-a4b-it`

Recommended conservative metadata:

- capabilities: `.streaming`, `.toolCalling`, `.vision`, `.reasoning`
- context window: `262_144`
- max output tokens:
  - `131_072` for `google/gemma-4-31b-it`
  - `262_144` for `google/gemma-4-26b-a4b-it`
- `reasoningConfig`: `.effort` with a conservative default like `.medium`
- `isFullySupported: true`
- keep `promptCaching`, `nativePDF`, `codeExecution`, `googleSearch`, and `googleMaps` **off** unless separately documented

## Review notes for impacted code paths

If another lane implements the catalog changes, these are the highest-value review points:

1. **Catalog exactness**
   - Add provider-specific exact IDs only where the public evidence is exact enough.
   - Gemini: `gemma-4-31b-it` only.
   - OpenRouter/Vercel: both `google/gemma-4-31b-it` and `google/gemma-4-26b-a4b-it`.
   - Do not add Vertex / Cloudflare Gemma 4 entries without stronger public exact-ID evidence.

2. **Capability discipline**
   - Do not inherit Gemini-family Google Search / Google Maps / code-execution affordances.
   - Treat Gemma 4 as a separate open-model family with only the capabilities explicitly documented by the provider pages.

3. **Resolver/test alignment**
   - Add exact-ID tests for:
     - `ModelCatalogTests`
     - `JinModelSupportTests`
     - `ModelSettingsResolverTests`
   - Ensure exact-match fallback still rejects suffix/prefix variants like `google/gemma-4-31b-it-custom`.

4. **UI heuristics**
   - If any UI grouping/order logic special-cases Google model families, keep Gemma 4 separate from Gemini-preview assumptions unless catalog metadata alone already drives the UI correctly.

## Result

As of **2026-04-04**, this review supports a conservative Jin rollout of **Gemma 4 exact-ID fully-supported metadata for Gemini (AI Studio) `gemma-4-31b-it`, plus Vercel AI Gateway and OpenRouter gateway IDs**.
