import SwiftUI

struct ContentPartView: View {
    let part: RenderedContentPart
    var isUser: Bool = false
    var deferCodeHighlightUpgrade: Bool = false
    var forceNativeText: Bool = false
    var payloadResolver: RenderedMessagePayloadResolver = .noop
    var selectionMessageID: UUID? = nil
    var selectionContextThreadID: UUID? = nil
    var selectionAnchorID: String? = nil
    var persistedHighlights: [MessageHighlightSnapshot] = []
    var selectionActions: MessageTextSelectionActions = .none

    var body: some View {
        switch part {
        case .text(let text):
            MessageTextView(
                text: text,
                mode: (isUser || forceNativeText) ? .plainText : .markdown,
                deferCodeHighlightUpgrade: (!isUser && deferCodeHighlightUpgrade),
                selectionMessageID: selectionMessageID,
                selectionContextThreadID: selectionContextThreadID,
                selectionAnchorID: selectionAnchorID,
                persistedHighlights: persistedHighlights,
                selectionActions: selectionActions
            )

        case .quote(let quote):
            MessageQuoteCardView(quote: quote)

        case .thinking(let thinking):
            ThinkingBlockView(thinking: thinking)

        case .redactedThinking:
            EmptyView()

        case .image(let image):
            renderedImage(image)

        case .video(let video):
            renderedVideo(video)

        case .file(let file):
            fileContentView(file)

        case .audio:
            Label("Audio content", systemImage: "waveform")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }
}
