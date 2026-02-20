import SwiftUI

struct MessageTextView: View {
    enum RenderingMode {
        case markdown
        case plainText
    }

    let text: String
    let mode: RenderingMode
    let deferCodeHighlightUpgrade: Bool

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue

    init(text: String, mode: RenderingMode = .markdown, deferCodeHighlightUpgrade: Bool = false) {
        self.text = text
        self.mode = mode
        self.deferCodeHighlightUpgrade = deferCodeHighlightUpgrade
    }

    init(normalizedMarkdownText: String) {
        self.text = normalizedMarkdownText
        self.mode = .markdown
        self.deferCodeHighlightUpgrade = false
    }

    var body: some View {
        switch mode {
        case .markdown:
            MarkdownWebRenderer(markdownText: text, deferCodeHighlightUpgrade: deferCodeHighlightUpgrade)

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
