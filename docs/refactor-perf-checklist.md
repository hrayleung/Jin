# Refactor Performance Checklist

Manual smoke checks for the elegance / performance refactor program. Run after
hot-path changes (streaming, timeline, attachments, networking).

## Streaming

- [ ] Stream a long reasoning reply (~2k+ tokens) with code blocks — scroll stays smooth
- [ ] Stream an artifact-heavy reply — no multi-second main-thread stalls per flush
- [ ] Tool-call + web-search activity during stream — sidebar/composer remain responsive
- [ ] Cancel mid-stream — UI settles without leftover streaming row

## Long conversations

- [ ] Open a 200+ message conversation — first paint without multi-second freeze
- [ ] Scroll rapidly through code blocks — resident text views stay viewport-bound
- [ ] Send a new message at the bottom of a long single-thread chat — no blank white stage

## Attachments / media

- [ ] Attach 5 large images to the draft composer — thumbnails appear without RAM spike
- [ ] Open a conversation with multiple videos — only visible players stay active
- [ ] Image generation response — image appears after stream end without freezing scroll

## Networking (SSE)

- [ ] High-token-rate provider stream (e.g. Groq / Cerebras) — no parser-related lag
- [ ] Partial chunk boundaries still reassemble correctly (regression covered by unit tests)

## Catalog / model add path

- [ ] Add a fully-supported model via catalog record + features (when migrated)
- [ ] `swift test --filter ModelCatalogConsistencyTests` green
- [ ] `swift test --filter ModelCapabilityRegistryTests` green

## Notes

- Do **not** reintroduce full-message WebView markdown for chat body.
- Do **not** put SwiftUI `Material` on scroll/hover chat surfaces.
- Prefer Instruments Time Profiler + Allocations for any new streaming UI work.
