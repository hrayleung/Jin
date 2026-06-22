import AppKit
import SwiftUI
import SwiftMath

/// Renders a display-math block (`$$…$$` / `\[…\]`) NATIVELY via SwiftMath's
/// Core Text typesetter — no `WKWebView`, no KaTeX. We parse first
/// (`MathRenderer.prepare`); a clean parse becomes an `MTMathUILabel` whose
/// size is known synchronously (so it fits the recycling table's `heightOfRow`
/// path), while a parse failure or still-streaming/unbalanced LaTeX degrades to
/// the raw source shown as selectable text.
struct MathBlockView: View {
    let latex: String
    @Environment(\.markdownTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.markdownMathSourceActions) private var mathActions

    var body: some View {
        content
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu { sourceMenu }
    }

    @ViewBuilder
    private var content: some View {
        switch MathRenderer.prepare(latex) {
        case .rendered(let mathList):
            NativeMathDisplay(
                mathList: mathList,
                fontSize: theme.bodyFont.pointSize,
                textColor: theme.baseColor,
                colorScheme: colorScheme
            )
        case .raw(let source):
            RawLatexText(source: source, theme: theme)
        }
    }

    /// The rendered `MTMathUILabel` is not part of the selectable flat text, so
    /// (unlike inline math) a display block can't be reached by drag-select —
    /// only the parse-failure `RawLatexText` is selectable. A context menu
    /// gives both render states a uniform, discoverable Copy/Quote affordance
    /// carrying the delimited `$$…$$` source so it round-trips as display math.
    @ViewBuilder
    private var sourceMenu: some View {
        let source = delimitedSource
        Button("Copy LaTeX") { mathActions.copy(source) }
        if let quote = mathActions.quote {
            Button("Quote LaTeX") { quote(source) }
        }
    }

    private var delimitedSource: String {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        return "$$\n\(trimmed)\n$$"
    }
}

// MARK: - Math source actions (Copy / Quote)

/// Copy/Quote actions for a standalone math block's raw LaTeX source, injected
/// by `NativeMarkdownView`. `quote` is nil when the surrounding anchor isn't
/// quotable (user messages / no selection context), so the menu item hides.
struct MarkdownMathSourceActions {
    let copy: (String) -> Void
    let quote: ((String) -> Void)?
}

private struct MarkdownMathSourceActionsKey: EnvironmentKey {
    static let defaultValue = MarkdownMathSourceActions(copy: { _ in }, quote: nil)
}

extension EnvironmentValues {
    var markdownMathSourceActions: MarkdownMathSourceActions {
        get { self[MarkdownMathSourceActionsKey.self] }
        set { self[MarkdownMathSourceActionsKey.self] = newValue }
    }
}

// MARK: - Native rendered math

/// `NSViewRepresentable` around `MTMathUILabel`. Reports its content size
/// synchronously through `sizeThatFits`, and re-resolves its (dynamic) text
/// color whenever the color scheme flips.
private struct NativeMathDisplay: NSViewRepresentable {
    let mathList: MTMathList
    let fontSize: CGFloat
    let textColor: NSColor
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.labelMode = .display
        label.textAlignment = .left
        // A touch of vertical breathing room; horizontal handled by the cell.
        label.contentInsets = MTEdgeInsets(top: 1, left: 0, bottom: 1, right: 0)
        configure(label)
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        configure(label)
    }

    private func configure(_ label: MTMathUILabel) {
        label.fontSize = fontSize
        label.textColor = MathColorResolver.resolve(textColor, for: colorScheme)
        // Avoid re-stringifying an unchanged list (the parsed list is cached, so
        // identity is stable for a given source); set only when it actually changes.
        if label.mathList !== mathList {
            label.mathList = mathList
        }
    }

    /// Synchronous sizing. When SwiftUI proposes a finite width we feed it to
    /// SwiftMath's `preferredMaxLayoutWidth` so long equations wrap (its native
    /// interatom line breaking) instead of overflowing the bubble.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MTMathUILabel, context: Context) -> CGSize? {
        if let width = proposal.width, width.isFinite, width > 0 {
            nsView.preferredMaxLayoutWidth = width
            let size = nsView.sizeThatFits(CGSize(width: width, height: 0))
            return CGSize(width: min(size.width, width), height: max(0, size.height))
        }
        let size = nsView.intrinsicContentSize
        return CGSize(width: max(0, size.width), height: max(0, size.height))
    }
}

// MARK: - Native degradation (no WebView)

/// Shown when SwiftMath can't parse the block (unsupported construct, or an
/// incomplete equation mid-stream). Presents the raw LaTeX as selectable
/// monospace text — the accepted native degradation: the user can still read,
/// copy, and edit the source.
private struct RawLatexText: View {
    let source: String
    let theme: MarkdownTheme

    var body: some View {
        Text(source)
            .font(.system(size: theme.codeFont.pointSize, design: .monospaced))
            .foregroundStyle(Color(nsColor: theme.secondaryColor))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}
