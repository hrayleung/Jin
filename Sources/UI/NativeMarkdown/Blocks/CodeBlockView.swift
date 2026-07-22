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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                if showLineNumbers {
                    // Laid out through the SAME TextKit paragraph style + font +
                    // top inset as the code so the numbers stay aligned with the
                    // code lines (a plain SwiftUI Text ignored the code's 1.3×
                    // lineHeightMultiple, so numbers crept upward). It's also a
                    // real NSView that forwards vertical wheels to the timeline,
                    // so the gutter strip isn't a scroll dead-zone.
                    CodeLineNumberGutterView(
                        count: lines.count,
                        font: theme.codeFont,
                        verticalInset: Self.codeVerticalInset
                    )
                    Rectangle()
                        .fill(JinSemanticColor.borderSubtle)
                        .frame(width: 1)
                        .padding(.vertical, 6)
                }
                HighlightedCodeView(
                    source: source,
                    language: language,
                    isStreamingTail: isStreamingTail,
                    theme: theme,
                    isDarkMode: isDarkMode,
                    deferHighlightUpgrade: deferHighlightUpgrade
                )
            }
        }
    }
}

private struct HighlightedCodeView: NSViewRepresentable {
    let source: String
    let language: String?
    let isStreamingTail: Bool
    let theme: MarkdownTheme
    let isDarkMode: Bool
    let deferHighlightUpgrade: Bool

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
        let proposedWidth = proposal.width
        let layoutWidth: CGFloat
        let isConstrained: Bool
        if let w = proposedWidth, w.isFinite, w > 0 {
            isConstrained = true
            layoutWidth = w
        } else {
            isConstrained = false
            layoutWidth = 10_000
        }
        let height = nsView.computeHeight(forWidth: layoutWidth)
        let width: CGFloat
        if isConstrained {
            width = layoutWidth
        } else {
            width = nsView.naturalWidth(maxWidth: layoutWidth)
        }
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

        // Establish text + final layout metrics immediately. Syntax coloring
        // is layout-neutral and upgrades asynchronously, so Highlight.js can
        // never block AppKit's sizing pass or the main thread.
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

    private static let horizontalInset: CGFloat = 8

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
        apply(to: nsView)
        return nsView.naturalSize()
    }

    private func apply(to view: CodeLineNumberTextView) {
        view.textContainerInset = NSSize(width: Self.horizontalInset, height: verticalInset)
        view.textStorage?.setAttributedString(Self.attributedNumbers(count: count, font: font))
    }

    private static func attributedNumbers(count: Int, font: NSFont) -> NSAttributedString {
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

    override func scrollWheel(with event: NSEvent) {
        switch wheelRouter.route(event: event, from: self) {
        case .forwardToTimeline(let timeline):
            timeline.scrollWheel(with: event)
        case .passToSuper:
            super.scrollWheel(with: event)
        }
    }

    /// Glyph extent plus the symmetric text-container inset — the gutter's
    /// natural (non-wrapping) size.
    func naturalSize() -> NSSize {
        guard let textContainer, let layoutManager else { return .zero }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: ceil(used.width) + textContainerInset.width * 2,
            height: ceil(used.height) + textContainerInset.height * 2
        )
    }
}
