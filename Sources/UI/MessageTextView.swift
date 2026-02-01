import SwiftUI
import MarkdownView

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
                MarkdownView(text)
                    .font(.body)
                    .markdownMathRenderingEnabled()
                    .fixedSize(horizontal: false, vertical: true)

            case .plainText:
                Text(text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
    }
}
