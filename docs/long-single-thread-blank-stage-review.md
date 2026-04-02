# Long single-thread blank stage review

## Symptom

In an ordinary single-thread conversation with a long history, sending a new user message can leave the main message stage looking blank white while the sidebar remains visible.

## Strongest code-path finding

The single-thread stage renders a moving suffix window instead of the full message list:

- `Sources/UI/ChatView+StageViews.swift:60-91` passes `singleThreadRenderContext.visibleMessages` into `ChatSingleThreadMessagesView`.
- `Sources/UI/ChatMessageStageViews.swift:219-230` computes `Array(allMessages.suffix(messageRenderLimit))`.

Once `allMessages.count > messageRenderLimit`, every send shifts the render window: one row falls off the top while a new row is appended at the bottom.

## Why this can blank the stage

`ChatSingleThreadMessagesView` uses a plain vertical `ScrollView` with delayed bottom refreshes:

- `Sources/UI/ChatMessageStageViews.swift:306-321` reacts to message-count and content-height changes.
- `Sources/UI/ChatMessageStageViews.swift:403-447` performs delayed `scrollTo("bottom", anchor: .bottom)` refreshes.

The single-thread scroll view does **not** set `.defaultScrollAnchor(.bottom)`, so when the suffix window shifts during a long-chat send, SwiftUI can preserve an offset that no longer maps cleanly onto the new content window. That can temporarily show a white viewport until the delayed bottom refresh lands.

Relevant contrast:

- Single-thread view: no default bottom anchor in `Sources/UI/ChatMessageStageViews.swift:223-327`
- Multi-thread columns: `.defaultScrollAnchor(.bottom)` is present in `Sources/UI/ChatMessageStageViews.swift:678-696`

## Secondary review finding

Long chats also switch to the async render-context builder:

- `Sources/UI/ChatView+MessageCaching.swift:33-103`

That remains a worthwhile guardrail area because the long-chat path depends on `makeDecodedRenderContext`, but the strongest blank-stage symptom match is still the moving render window plus missing default bottom anchoring in the single-thread stage.

## Recommended verification focus

1. Reproduce with `allMessages.count > messageRenderLimit` while pinned near bottom.
2. Verify whether the white viewport disappears if the single-thread scroll view gets a stable bottom anchor / immediate bottom restore when the suffix window shifts.
3. Keep an async-cache regression check as a secondary guardrail for long-history rebuilds.
