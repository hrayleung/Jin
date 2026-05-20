import SwiftUI

struct MathBlockView: View {
    let latex: String
    @State private var height: CGFloat = 36

    var body: some View {
        MiniWebViewHost(
            templateName: "native-markdown-katex",
            renderFunction: "renderMath",
            payload: latex,
            height: $height
        )
        .frame(height: max(36, height))
        .padding(.vertical, 4)
    }
}
