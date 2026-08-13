import AppKit
import SwiftUI

/// Native code block. Header carries language label + copy + manual fold +
/// line-numbers toggle; body shows syntax-highlighted code with optional
/// line numbers. Soft-collapse "Show N more lines" was the WebView era's
/// affordance and has been removed — long blocks render fully and users
/// can collapse them via the chevron in the header.
@MainActor
struct CodeBlockView: View {
    let language: String?
    let source: String
    let isStreamingTail: Bool

    @AppStorage(AppPreferenceKeys.codeBlockShowLineNumbers) private var prefShowLineNumbers = false

    @State private var lineNumbersOverride: Bool? = nil
    @State private var isCollapsed: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.markdownTheme) private var theme
    @Environment(\.markdownDefersCodeHighlightUpgrade) private var deferHighlightUpgrade

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                    .opacity(0.5)
                CodeBlockBody(
                    source: source,
                    language: language,
                    isStreamingTail: isStreamingTail,
                    showLineNumbers: showLineNumbers,
                    theme: theme,
                    isDarkMode: colorScheme == .dark,
                    deferHighlightUpgrade: deferHighlightUpgrade
                )
            }
        }
        .background(JinSemanticColor.subtleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(JinSemanticColor.borderSubtle, lineWidth: JinStrokeWidth.regular)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: JinSemanticColor.shadowElevated.opacity(0.6), radius: 10, x: 0, y: 4)
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: iconSymbol(forLanguage: language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconTint(forLanguage: language))
                .frame(width: 14)
            Text(displayLanguage)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if shouldShowFoldToggle {
                Button(action: { isCollapsed.toggle() }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand code" : "Collapse code")
            }
            Button(action: { lineNumbersOverride = !showLineNumbers }) {
                Image(systemName: showLineNumbers ? "list.number" : "list.dash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(showLineNumbers ? Color.accentColor : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(showLineNumbers ? "Hide line numbers" : "Show line numbers")
            if !isStreamingTail {
                CopyToPasteboardButton(text: source, helpText: "Copy code", useProminentStyle: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var displayLanguage: String {
        if let language, !language.isEmpty { return language }
        return "text"
    }

    private var showLineNumbers: Bool {
        lineNumbersOverride ?? prefShowLineNumbers
    }

    private var shouldShowFoldToggle: Bool {
        !isStreamingTail && lineCount > 1
    }

    private var lineCount: Int {
        source.reduce(into: 1) { count, char in
            if char == "\n" { count += 1 }
        }
    }

    private func iconSymbol(forLanguage language: String?) -> String {
        let normalized = LanguageAliases.normalize(language) ?? ""
        let candidate: String
        switch normalized {
        case "swift": candidate = "swift"
        case "html": candidate = "globe"
        case "css": candidate = "paintbrush.fill"
        case "json": candidate = "curlybraces"
        case "yaml": candidate = "doc.text"
        case "bash": candidate = "terminal.fill"
        case "sql": candidate = "cylinder.split.1x2"
        case "markdown", "md": candidate = "text.alignleft"
        case "diff": candidate = "plus.forwardslash.minus"
        case "mermaid": candidate = "flowchart"
        case "math", "latex", "tex": candidate = "function"
        // No SF Symbol covers most language logos (python, js, ts, go,
        // rust, etc.) — rely on the language label + tint color to convey
        // identity, with the generic code icon as the glyph.
        default: candidate = "chevron.left.forwardslash.chevron.right"
        }
        // Defensive: if the chosen name turns out not to be a valid SF
        // Symbol on this OS version, fall back to the generic icon so the
        // header doesn't render an empty space.
        if NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
            return candidate
        }
        return "chevron.left.forwardslash.chevron.right"
    }

    private func iconTint(forLanguage language: String?) -> Color {
        let normalized = LanguageAliases.normalize(language) ?? ""
        switch normalized {
        case "swift": return Color(red: 0.94, green: 0.37, blue: 0.17)
        case "python": return Color(red: 0.30, green: 0.51, blue: 0.74)
        case "javascript": return Color(red: 0.94, green: 0.84, blue: 0.18)
        case "typescript": return Color(red: 0.18, green: 0.46, blue: 0.78)
        case "go": return Color(red: 0.04, green: 0.68, blue: 0.86)
        case "rust": return Color(red: 0.85, green: 0.40, blue: 0.18)
        case "html": return Color(red: 0.90, green: 0.36, blue: 0.20)
        case "css": return Color(red: 0.15, green: 0.45, blue: 0.78)
        case "bash": return Color(red: 0.31, green: 0.31, blue: 0.31)
        case "json": return Color(red: 0.66, green: 0.40, blue: 0.20)
        case "sql": return Color(red: 0.40, green: 0.40, blue: 0.45)
        case "mermaid": return Color(red: 0.86, green: 0.36, blue: 0.55)
        case "math", "latex", "tex": return Color(red: 0.45, green: 0.35, blue: 0.78)
        default: return Color.secondary
        }
    }
}

private struct CodeBlockBody: View {
    let source: String
    let language: String?
    let isStreamingTail: Bool
    let showLineNumbers: Bool
    let theme: MarkdownTheme
    let isDarkMode: Bool
    let deferHighlightUpgrade: Bool

    /// Top/bottom inset of the code text view (`HighlightedCodeView` sets the
    /// same value on its `textContainerInset.height`). The gutter matches it so
    /// the first line number sits at the first code line's baseline.
    static let codeVerticalInset: CGFloat = 10

    private var lines: [String] {
        source.components(separatedBy: "\n")
    }

    /// Width of the block as laid out on screen, read from the scroll view's
    /// own frame. The code text view is stretched to fill whatever is left of
    /// it (see `HighlightedCodeView.minimumWidth`) so that the ENTIRE card is
    /// a view we own.
    ///
    /// Why that matters: short code (`git show abc1234`) leaves most of a
    /// full-width card empty, and that empty area belongs to the SwiftUI
    /// horizontal scroll view — which eats vertical wheel deltas. Only the
    /// code text view and the gutter forward them to the timeline, so hovering
    /// the empty part froze the page. Long code always filled the card, which
    /// is why this only ever reproduced "sometimes".
    @State private var viewportWidth: CGFloat = 0

    private var gutterWidth: CGFloat {
        guard showLineNumbers else { return 0 }
        // Includes the trailing 1pt divider drawn by CodeLineNumberTextView so
        // there is no SwiftUI-only strip between gutter and code (that strip
        // hit-tested as DocumentView and became a wheel dead-zone on CI).
        return CodeLineNumberGutter.size(
            count: lines.count,
            font: theme.codeFont,
            inset: NSSize(width: CodeLineNumberGutter.horizontalInset, height: Self.codeVerticalInset)
        ).width
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                if showLineNumbers {
                    // Laid out through the SAME TextKit paragraph style + font +
                    // top inset as the code so the numbers stay aligned with the
                    // code lines (a plain SwiftUI Text ignored the code's 1.3×
                    // lineHeightMultiple, so numbers crept upward). It's also a
                    // real NSView that forwards vertical wheels to the timeline,
                    // so the gutter strip isn't a scroll dead-zone. The trailing
                    // divider is drawn inside this view (not a separate
                    // Rectangle) so every hover pixel over the gutter column
                    // lands on a wheel-forwarding NSView.
                    CodeLineNumberGutterView(
                        count: lines.count,
                        font: theme.codeFont,
                        verticalInset: Self.codeVerticalInset
                    )
                }
                HighlightedCodeView(
                    source: source,
                    language: language,
                    isStreamingTail: isStreamingTail,
                    theme: theme,
                    isDarkMode: isDarkMode,
                    deferHighlightUpgrade: deferHighlightUpgrade,
                    minimumWidth: max(0, viewportWidth - gutterWidth)
                )
            }
        }
        // Measurement only — a background GeometryReader does not affect the
        // scroll view's own layout.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewportWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in viewportWidth = newWidth }
            }
        )
    }
}

private struct HighlightedCodeView: NSViewRepresentable {
    let source: String
    let language: String?
    let isStreamingTail: Bool
    let theme: MarkdownTheme
    let isDarkMode: Bool
    let deferHighlightUpgrade: Bool
    /// Stretch to at least this wide so the whole code card is this view (and
    /// therefore forwards vertical wheels). Never causes wrapping: the width
    /// used is always >= the text's natural width.
    var minimumWidth: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> JinMessageTextView {
        let view = JinMessageTextView()
        view.isSelectable = true
        applyAttributedString(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: JinMessageTextView, context: Context) {
        applyAttributedString(to: nsView, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: JinMessageTextView, context: Context) -> CGSize? {
        // Code NEVER wraps — it scrolls sideways — so the width used is always
        // at least the text's natural width, and the height that follows is
        // the unwrapped height the recycling table's row heights depend on
        // (see ChatTimelineHeightEstimatorTests.testCodeFenceContentNotPricedAsWrappedProse).
        // Above that floor we take the widest of the proposal and
        // `minimumWidth`, which fills the card so no part of it belongs to the
        // wheel-eating scroll view.
        let natural = nsView.naturalWidth(maxWidth: 10_000)
        let proposed = (proposal.width?.isFinite == true) ? (proposal.width ?? 0) : 0
        let width = max(natural, max(minimumWidth, proposed))
        let height = nsView.computeHeight(forWidth: width)
        return CGSize(width: max(1, width), height: max(1, height))
    }

    private func applyAttributedString(to view: JinMessageTextView, coordinator: Coordinator) {
        let fingerprint = Fingerprint(
            source: source,
            language: language,
            isStreamingTail: isStreamingTail,
            theme: theme,
            isDarkMode: isDarkMode,
            deferHighlightUpgrade: deferHighlightUpgrade
        )
        guard coordinator.lastRequestedFingerprint != fingerprint else { return }
        coordinator.highlightTask?.cancel()
        coordinator.lastRequestedFingerprint = fingerprint

        // Establish text immediately so Highlight.js never blocks AppKit's
        // sizing pass or the main thread. The async upgrade is NOT
        // layout-neutral: the renderer preserves bold/italic traits from the
        // theme, and bold/italic CJK fallback fonts have different metrics —
        // wraps (and therefore height) can change, so `apply` must re-signal
        // sizing after every swap.
        let immediate = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.baseColor,
                .paragraphStyle: theme.codeParagraphStyle,
            ]
        )
        apply(immediate, to: view)

        let source = source
        let language = language
        let theme = theme
        let isDarkMode = isDarkMode
        let useFastFallback = isStreamingTail || deferHighlightUpgrade
        let priority: TaskPriority = deferHighlightUpgrade ? .utility : .userInitiated
        let work = Task.detached(priority: priority) {
            guard !Task.isCancelled else { return SendableHighlightedString?.none }
            let highlighted = MarkdownSyntaxHighlighter.highlight(
                source,
                language: language,
                theme: theme,
                isDarkMode: isDarkMode,
                useFastFallback: useFastFallback
            )
            guard !Task.isCancelled else { return SendableHighlightedString?.none }
            let withParagraphStyle = NSMutableAttributedString(attributedString: highlighted)
            withParagraphStyle.addAttribute(
                .paragraphStyle,
                value: theme.codeParagraphStyle,
                range: NSRange(location: 0, length: withParagraphStyle.length)
            )
            return SendableHighlightedString(value: withParagraphStyle)
        }
        coordinator.highlightTask = Task { @MainActor [weak view, weak coordinator] in
            let result = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard !Task.isCancelled,
                  let view,
                  let coordinator,
                  coordinator.lastRequestedFingerprint == fingerprint,
                  let result else { return }
            apply(result.value, to: view)
            coordinator.highlightTask = nil
        }
    }

    private func apply(_ attributedString: NSAttributedString, to view: JinMessageTextView) {
        let selectedRange = view.selectedRange()
        view.setScrubbedAttributedString(attributedString)
        view.setSelectedRange(
            clamped(range: selectedRange, length: attributedString.length)
        )
        view.textContainerInset = NSSize(width: 14, height: CodeBlockBody.codeVerticalInset)
        // Same trio as AttributedTextBlock.applyAttributedString. The async
        // highlight upgrade lands outside any SwiftUI update, so without an
        // explicit intrinsic invalidation nobody re-reads the (already
        // invalidated) height memo and a wrap change from bold/italic
        // upgrades leaves the row at a stale height — clipped at the bottom
        // by the hosting cell's mask.
        view.invalidateHeightCache()
        view.invalidateIntrinsicContentSize()
        view.needsDisplay = true
    }

    private func clamped(range: NSRange, length: Int) -> NSRange {
        let location = min(range.location, length)
        let remaining = max(0, length - location)
        return NSRange(location: location, length: min(range.length, remaining))
    }

    final class Coordinator {
        var lastRequestedFingerprint: Fingerprint?
        var highlightTask: Task<Void, Never>?

        deinit {
            highlightTask?.cancel()
        }
    }

    fileprivate struct Fingerprint: Equatable {
        let source: String
        let language: String?
        let isStreamingTail: Bool
        let theme: MarkdownTheme
        let isDarkMode: Bool
        let deferHighlightUpgrade: Bool
    }
}

private struct SendableHighlightedString: @unchecked Sendable {
    let value: NSAttributedString
}

/// Right-aligned line-number gutter laid out through TextKit with the code's
/// own `codeParagraphStyle` (matching `lineHeightMultiple`), font, and vertical
/// inset — so the numbers line up with the code lines fragment-for-fragment. A
/// plain SwiftUI `Text` ignored the 1.3× line-height multiplier and the numbers
/// drifted upward. The numbers are space-padded to a fixed digit width, which
/// right-justifies them in the monospaced code font without needing the
/// container-width gymnastics that paragraph `.right` alignment would require.
private struct CodeLineNumberGutterView: NSViewRepresentable {
    let count: Int
    let font: NSFont
    let verticalInset: CGFloat


    func makeNSView(context: Context) -> CodeLineNumberTextView {
        let view = CodeLineNumberTextView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CodeLineNumberTextView, context: Context) {
        apply(to: nsView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: CodeLineNumberTextView,
        context: Context
    ) -> CGSize? {
        // Do NOT apply here. `sizeThatFits` runs inside AppKit's layout cycle,
        // and writing into a text storage while its layout manager may be
        // typesetting is what corrupts TextKit (see the matching note in
        // `AttributedTextBlock.sizeThatFits` — same defect, same crash class).
        // The gutter's size is a pure function of the number of lines and the
        // font, so it needs no live view at all.
        let inset = NSSize(width: CodeLineNumberGutter.horizontalInset, height: verticalInset)
        return CodeLineNumberGutter.size(count: count, font: font, inset: inset)
    }

    private func apply(to view: CodeLineNumberTextView) {
        view.textContainerInset = NSSize(width: CodeLineNumberGutter.horizontalInset, height: verticalInset)
        view.textStorage?.setAttributedString(CodeLineNumberGutter.attributedNumbers(count: count, font: font))
        view.invalidateIntrinsicContentSize()
    }

}

/// Line-number gutter content + metrics, shared by the representable and the
/// measurement parity test so the two can never drift.
enum CodeLineNumberGutter {
    static let horizontalInset: CGFloat = 8
    /// Trailing 1pt rule between gutter and code, drawn by `CodeLineNumberTextView`.
    static let trailingDividerWidth: CGFloat = 1
    /// Vertical inset of the trailing divider (matches the previous SwiftUI Rectangle padding).
    static let trailingDividerVerticalInset: CGFloat = 6

    /// Memoized: the gutter's size depends only on the line count, the font
    /// and the inset, and every code block on screen asks for it on every
    /// layout pass.
    private static var sizeCache: [String: NSSize] = [:]

    @MainActor
    static func size(count: Int, font: NSFont, inset: NSSize) -> NSSize {
        let key = "\(count):\(font.fontName):\(font.pointSize):\(inset.width)x\(inset.height):div\(trailingDividerWidth)"
        if let cached = sizeCache[key] { return cached }
        var measured = JinTextMeasurementStack.size(
            of: attributedNumbers(count: count, font: font),
            token: JinTextMeasurementStack.Token(key: "gutter:" + key, version: 0),
            inset: inset
        )
        measured.width += trailingDividerWidth
        sizeCache[key] = measured
        return measured
    }

    static func attributedNumbers(count: Int, font: NSFont) -> NSAttributedString {
        let total = max(1, count)
        let digitWidth = String(total).count
        let body = (1...total)
            .map { String(format: "%\(digitWidth)d", $0) }
            .joined(separator: "\n")
        return NSAttributedString(
            string: body,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                // The code's own paragraph style → identical per-line fragment
                // height, so numbers track the code lines exactly.
                .paragraphStyle: MarkdownTheme.cachedCodeParagraphStyle,
            ]
        )
    }
}

/// Minimal, non-selecting `NSTextView` for the line-number gutter. Lays the
/// numbers out with the code's paragraph style and forwards vertical-dominant
/// wheel events to the chat timeline (like the code text view), so the gutter
/// strip scrolls the page instead of trapping it. Deliberately NOT a
/// `JinMessageTextView` — it carries no selection/aggregator machinery and
/// stays out of the resident-text-view census.
final class CodeLineNumberTextView: NSTextView {
    private var wheelRouter = CodeBlockWheelRouter()

    override var isOpaque: Bool { false }

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = false
        isRichText = false
        drawsBackground = false
        backgroundColor = .clear
        isHorizontallyResizable = true
        isVerticallyResizable = true
        textContainerInset = .zero
        autoresizingMask = []
        isAutomaticTextCompletionEnabled = false
        wantsLayer = true
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// SwiftUI on some CI/AppKit paths sizes the representable from
    /// `intrinsicContentSize` instead of `sizeThatFits`. That path used to
    /// omit the trailing divider, leaving a 1pt DocumentView strip at the
    /// gutter/code seam (`testShortCodeFillsTheCardWithForwardingViews` on
    /// GitHub-hosted runners).
    override var intrinsicContentSize: NSSize {
        naturalSize()
    }

    override func scrollWheel(with event: NSEvent) {
        switch wheelRouter.route(event: event, from: self) {
        case .forwardToTimeline(let timeline):
            timeline.scrollWheel(with: event)
        case .passToSuper:
            super.scrollWheel(with: event)
        }
    }

    /// Same inset click-through as `JinMessageTextView`: the gutter's 8pt
    /// horizontal padding has no glyphs, and a `nil` hit lands on DocumentView.
    override func hitTest(_ point: NSPoint) -> NSView? {
        CodeBlockHitTesting.hitTest(self, pointInSuperview: point, superHit: super.hitTest(point))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Trailing divider lives on this wheel-forwarding view so the gutter /
        // code seam is never a SwiftUI-only DocumentView dead-zone.
        let dividerWidth = CodeLineNumberGutter.trailingDividerWidth
        let verticalInset = CodeLineNumberGutter.trailingDividerVerticalInset
        let divider = NSRect(
            x: bounds.maxX - dividerWidth,
            y: verticalInset,
            width: dividerWidth,
            height: max(0, bounds.height - verticalInset * 2)
        )
        guard divider.intersects(dirtyRect) else { return }
        NSColor.separatorColor.setFill()
        divider.fill()
    }

    /// Glyph extent plus the symmetric text-container inset and trailing
    /// divider — the gutter's natural (non-wrapping) size.
    func naturalSize() -> NSSize {
        guard let textContainer, let layoutManager else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: ceil(used.width) + textContainerInset.width * 2 + CodeLineNumberGutter.trailingDividerWidth,
            height: ceil(used.height) + textContainerInset.height * 2
        )
    }
}
