# Evidence sheet (one per provider + exact ID)

Copy this into the working notes. Do not write Swift until every required row is `cited` or `unknown → conservative`.

```
## Identity
- ProviderType:
- Exact API ID:
- Aliases / dated snapshots (each is its own sheet or an identical cited twin):
- Display name:
- Live in API? (yes/no, how confirmed):
- Official URLs (fetched date):
  - model page:
  - API / params page:
  - changelog / deprecations:
- Hint sources (not evidence):

## Limits
- Context window:
- Max output tokens:          # nil if undocumented
- Source quote / table:

## Modalities
- Input: text / image / audio / video / PDF
- Output: text / image / audio / video
- .vision:
- .audio:
- .videoInput:                # live probe required; else false
- .nativePDF:                 # adapter must be able to send
- .imageGeneration / .videoGeneration:

## Tools & extras
- .toolCalling:
- .streaming:
- .promptCaching:
- .codeExecution:             # registry allowlist, not just catalog bit
- Web search:                 # registry, provider-specific
- Google Search / Maps:       # Gemini/Vertex/OpenRouter lists are distinct
- Prompt cache mechanism:

## Reasoning
- .reasoning:
- Config type: effort / budget / toggle / none
- Allowed efforts (exact wire values):
- Default effort / budget:
- Can disable? (what happens if the field is omitted vs explicit none/disabled)
- Always-on list needed?
- Provider-only: verbosity / pro mode / reasoning.context / thinking.display / speed

## Sampling
- temperature / top_p / top_k accepted?
- Only when reasoning off?
- Strip in which request builder?

## Request shape
- openAIResponses / openAICompatible / anthropic / gemini
- OpenCode Go endpoint if applicable:
- Extra headers / body fields:
- Fields that 400 if sent:

## Jin grade
- isFullySupported:
- isSeeded:                   # first-launch picker only
- Gateway mirrors to add (separate IDs):
- Unverified fields (must stay conservative):

## Tests to add
- Catalog exact + sibling fallback:
- Fully-supported exact / false sibling:
- Resolver stale persisted ModelInfo:
- Registry effort / search / code exec:
- Adapter request:
- videoInput allowlist (only after probe):
```

## Video-input probe (required before `.videoInput`)

Do not substitute a 200 OK. Send a short synthetic clip with known ground truth (four solid colour segments: red, yellow, blue, black) and require the model to name the colours in order.

Record: date, provider, exact ID, endpoint (`/chat/completions` vs `/messages` vs `generateContent`), result.

If you cannot probe, leave `.videoInput` off.

## Conservative defaults (when unknown)

- capabilities: `[.streaming, .toolCalling]` only if you are **not** adding a catalog row; if you add a row, include only cited bits
- contextWindow: do not invent; if the model must be catalogued and context is unknown, do not mark fully-supported
- maxOutputTokens: `nil`
- reasoningConfig: `nil` and no `.reasoning`
- isFullySupported: `false`
- isSeeded: `false`
- web search / code execution / maps / native PDF / videoInput: off
