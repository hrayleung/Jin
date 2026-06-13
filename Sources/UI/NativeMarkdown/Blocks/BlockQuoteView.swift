import SwiftUI

struct BlockQuoteView: View {
    let children: [NativeMarkdownBlock]
    let path: [Int]
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(nsColor: theme.blockQuoteBorder))
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { offset, child in
                    NativeBlockView(block: child, path: path + [offset])
                }
            }
            .padding(.leading, 10)
            .padding(.vertical, 2)
            .foregroundStyle(Color(nsColor: theme.blockQuoteText))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
