import SwiftUI
import MarkdownView
#if canImport(LaTeXSwiftUI)
import LaTeXSwiftUI
#endif

struct MessageTextView: View {
    enum RenderingMode {
        case markdown
        case plainText
    }

    let text: String
    let mode: RenderingMode
    let normalizedMarkdownText: String?

    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.codeFontFamily) private var codeFontFamily = JinTypography.systemFontPreferenceValue
    @AppStorage(AppPreferenceKeys.chatMessageFontScale) private var chatMessageFontScale = JinTypography.defaultChatMessageScale

    init(text: String, mode: RenderingMode = .markdown) {
        self.text = text
        self.mode = mode
        self.normalizedMarkdownText = nil
    }

    init(normalizedMarkdownText: String) {
        self.text = normalizedMarkdownText
        self.mode = .markdown
        self.normalizedMarkdownText = normalizedMarkdownText
    }

    var body: some View {
        Group {
            switch mode {
            case .markdown:
                markdownBody

            case .plainText:
                Text(text)
                    .font(chatBodyFont)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var markdownBody: some View {
        let renderedMarkdown = normalizedMarkdownText ?? text.normalizingMathDelimitersForMarkdownView()

        #if canImport(LaTeXSwiftUI)
        configuredMarkdownView(renderedMarkdown)
            .renderingStyle(.empty)
            .ignoreStringFormatting()
            .fixedSize(horizontal: false, vertical: true)
        #else
        configuredMarkdownView(renderedMarkdown)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private func configuredMarkdownView(_ text: String) -> some View {
        MarkdownView(text)
            .font(chatBodyFont)
            .font(chatBodyFont, for: .body)
            .font(chatBodyFont, for: .blockQuote)
            .font(chatBodyFont, for: .tableBody)
            .font(chatBodyFont, for: .inlineMath)
            .font(chatBodyFont, for: .displayMath)
            .font(chatCodeFont, for: .codeBlock)
            .markdownMathRenderingEnabled()
    }

    private var chatBodyFont: Font {
        JinTypography.chatBodyFont(appFamilyPreference: appFontFamily, scale: chatMessageFontScale)
    }

    private var chatCodeFont: Font {
        JinTypography.chatCodeFont(codeFamilyPreference: codeFontFamily, scale: chatMessageFontScale)
    }
}
