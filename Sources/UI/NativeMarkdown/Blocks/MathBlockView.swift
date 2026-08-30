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
                colorScheme: colorScheme,
                copySource: delimitedSource
            )
            .help("Click to copy LaTeX")
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
        LatexSourceCopy.delimitedDisplaySource(latex)
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
    let copySource: String

    func makeCoordinator() -> Coordinator {
        Coordinator(source: copySource)
    }

    func makeNSView(context: Context) -> ClickableMathHost {
        let host = ClickableMathHost()
        let coordinator = context.coordinator
        host.onClick = { [weak host] in
            guard let host else { return }
            LatexSourceCopyPanel.present(
                source: coordinator.source,
                relativeTo: host.bounds,
                of: host
            )
        }
        configure(host, coordinator: coordinator)
        return host
    }

    func updateNSView(_ host: ClickableMathHost, context: Context) {
        configure(host, coordinator: context.coordinator)
    }

    private func configure(_ host: ClickableMathHost, coordinator: Coordinator) {
        coordinator.source = copySource
        host.latexSource = copySource
        host.label.fontSize = fontSize
        host.label.textColor = MathColorResolver.resolve(textColor, for: colorScheme)
        // Avoid re-stringifying an unchanged list (the parsed list is cached, so
        // identity is stable for a given source); set only when it actually changes.
        if host.label.mathList !== mathList {
            LatexSourceCopyPanel.dismissIfPresented(from: host)
            host.label.mathList = mathList
        }
    }

    final class Coordinator {
        var source: String
        init(source: String) { self.source = source }
    }

    /// Synchronous sizing. When SwiftUI proposes a finite width we feed it to
    /// SwiftMath's `preferredMaxLayoutWidth` so long equations wrap (its native
    /// interatom line breaking) instead of overflowing the bubble.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ClickableMathHost, context: Context) -> CGSize? {
        if let width = proposal.width, width.isFinite, width > 0 {
            nsView.label.preferredMaxLayoutWidth = width
            let size = nsView.label.sizeThatFits(CGSize(width: width, height: 0))
            return CGSize(width: min(size.width, width), height: max(0, size.height))
        }
        let size = nsView.label.intrinsicContentSize
        return CGSize(width: max(0, size.width), height: max(0, size.height))
    }
}

/// Host around `MTMathUILabel`. The vendor label is a non-open class, so
/// click-to-copy cannot subclass it; the host claims the hit test, turns a
/// click (not a drag) into the shared LaTeX copy popover, and paints a
/// pointing-hand cursor so the target is discoverable. Trackpad two-finger
/// scroll is unaffected — it never goes through `mouseDown`.
private final class ClickableMathHost: NSView {
    let label = MTMathUILabel()
    var onClick: (() -> Void)?
    var latexSource: String = ""
    private var downPointInWindow: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        label.labelMode = .display
        label.textAlignment = .left
        // A touch of vertical breathing room; horizontal handled by the cell.
        label.contentInsets = MTEdgeInsets(top: 1, left: 0, bottom: 1, right: 0)
        label.setAccessibilityElement(false)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = bounds
    }

    /// Claim every pixel of the equation so the vendor label cannot swallow
    /// the click. The host is sized to the math, so empty bubble space to the
    /// right is not part of this view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        downPointInWindow = event.clickCount == 1 ? event.locationInWindow : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downPointInWindow else { return }
        let dist = LatexSourceCopy.dragDistanceSquared(from: down, to: event.locationInWindow)
        if dist > LatexSourceCopy.clickSlop * LatexSourceCopy.clickSlop {
            downPointInWindow = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPointInWindow = nil }
        guard let down = downPointInWindow else { return }
        let dist = LatexSourceCopy.dragDistanceSquared(from: down, to: event.locationInWindow)
        guard LatexSourceCopy.isClick(
            dragDistanceSquared: dist,
            clickCount: event.clickCount,
            modifierFlags: event.modifierFlags
        ) else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return }
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            LatexSourceCopyPanel.dismissIfPresented(from: self)
        }
    }

    deinit {
        LatexSourceCopyPanel.dismissDetached(from: self)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role { .button }
    override func accessibilityLabel() -> String? { "Equation" }
    override func accessibilityValue() -> Any? { latexSource }
    override func accessibilityHelp() -> String? { "Shows LaTeX source to copy" }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
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
