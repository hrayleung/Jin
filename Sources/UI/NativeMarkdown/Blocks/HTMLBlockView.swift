import AppKit
import SwiftUI

/// Renders an HTML block literally — raw HTML execution is disabled in this
/// app's policy. Uses SwiftUI Text (no NSTextView allocation) since the
/// content is read-only and doesn't participate in cross-block selection.
struct HTMLBlockView: View {
    let text: String
    @Environment(\.markdownTheme) private var theme

    var body: some View {
        Text(text)
            .font(Font(theme.codeFont))
            .foregroundStyle(Color(nsColor: theme.baseColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: theme.inlineCodeBackground))
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small))
            .textSelection(.enabled)
            .padding(.vertical, 4)
    }
}
