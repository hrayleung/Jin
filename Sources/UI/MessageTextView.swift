import SwiftUI

struct MessageTextView: View {
    enum RenderingMode {
        case markdown
        case plainText
    }

    let text: String
    let mode: RenderingMode
    let deferCodeHighlightUpgrade: Bool
    let selectionMessageID: UUID?
    let selectionContextThreadID: UUID?
    let selectionAnchorID: String?
    let persistedHighlights: [MessageHighlightSnapshot]
    let selectionActions: MessageTextSelectionActions

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue

    init(
        text: String,
        mode: RenderingMode = .markdown,
        deferCodeHighlightUpgrade: Bool = false,
        selectionMessageID: UUID? = nil,
        selectionContextThreadID: UUID? = nil,
        selectionAnchorID: String? = nil,
        persistedHighlights: [MessageHighlightSnapshot] = [],
        selectionActions: MessageTextSelectionActions = .none
    ) {
        self.text = text
        self.mode = mode
        self.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
        self.selectionMessageID = selectionMessageID
        self.selectionContextThreadID = selectionContextThreadID
        self.selectionAnchorID = selectionAnchorID
        self.persistedHighlights = persistedHighlights
        self.selectionActions = selectionActions
    }

    init(normalizedMarkdownText: String) {
        self.text = normalizedMarkdownText
        self.mode = .markdown
        self.deferCodeHighlightUpgrade = false
        self.selectionMessageID = nil
        self.selectionContextThreadID = nil
        self.selectionAnchorID = nil
        self.persistedHighlights = []
        self.selectionActions = .none
    }

    var body: some View {
        switch mode {
        case .markdown:
            MarkdownWebRenderer(
                markdownText: text,
                deferCodeHighlightUpgrade: deferCodeHighlightUpgrade,
                selectionMessageID: selectionMessageID,
                selectionContextThreadID: selectionContextThreadID,
                selectionAnchorID: selectionAnchorID,
                persistedHighlights: persistedHighlights,
                selectionActions: selectionActions
            )

        case .plainText:
            Text(text)
                .font(chatBodyFont)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var chatBodyFont: Font {
        JinTypography.chatBodyFont(appFamilyPreference: appFontFamily, scale: JinTypography.defaultChatMessageScale)
    }
}
