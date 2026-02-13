import SwiftUI

struct MessageTextView: View {
    enum RenderingMode {
        case markdown
        case plainText
    }

    let text: String
    let mode: RenderingMode

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue

    init(text: String, mode: RenderingMode = .markdown) {
        self.text = text
        self.mode = mode
    }

    init(normalizedMarkdownText: String) {
        self.text = normalizedMarkdownText
        self.mode = .markdown
    }

    var body: some View {
        switch mode {
        case .markdown:
            MarkdownWebRenderer(markdownText: text)

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
