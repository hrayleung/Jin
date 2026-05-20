import SwiftUI

struct MermaidBlockView: View {
    let source: String
    @State private var height: CGFloat = 60

    var body: some View {
        MiniWebViewHost(
            templateName: "native-markdown-mermaid",
            renderFunction: "renderMermaid",
            payload: source,
            height: $height
        )
        .frame(height: max(60, height))
        .padding(.vertical, 4)
    }
}
