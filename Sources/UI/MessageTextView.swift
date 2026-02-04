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

    init(text: String, mode: RenderingMode = .markdown) {
        self.text = text
        self.mode = mode
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
        #if canImport(LaTeXSwiftUI)
        MarkdownView(text.normalizingMathDelimitersForMarkdownView())
            .font(.body)
            .markdownMathRenderingEnabled()
            .renderingStyle(.empty)
            .ignoreStringFormatting()
            .fixedSize(horizontal: false, vertical: true)
        #else
        MarkdownView(text.normalizingMathDelimitersForMarkdownView())
            .font(.body)
            .markdownMathRenderingEnabled()
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}
