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
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var markdownBody: some View {
        let renderedMarkdown = normalizedMarkdownText ?? text.normalizingMathDelimitersForMarkdownView()

        #if canImport(LaTeXSwiftUI)
        MarkdownView(renderedMarkdown)
            .font(.body)
            .markdownMathRenderingEnabled()
            .renderingStyle(.empty)
            .ignoreStringFormatting()
            .fixedSize(horizontal: false, vertical: true)
        #else
        MarkdownView(renderedMarkdown)
            .font(.body)
            .markdownMathRenderingEnabled()
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}
