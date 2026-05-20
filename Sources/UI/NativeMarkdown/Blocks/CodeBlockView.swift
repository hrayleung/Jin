import AppKit
import SwiftUI

/// Native code block. Header carries language label + copy + manual fold +
/// line-numbers toggle; body shows syntax-highlighted code with optional
/// line numbers. Soft-collapse "Show N more lines" was the WebView era's
/// affordance and has been removed — long blocks render fully and users
/// can collapse them via the chevron in the header.
struct CodeBlockView: View {
    let language: String?
    let source: String
    let isStreamingTail: Bool

    @AppStorage(AppPreferenceKeys.codeBlockShowLineNumbers) private var prefShowLineNumbers = false

    @State private var lineNumbersOverride: Bool? = nil
    @State private var isCollapsed: Bool = false

    @Environment(\.markdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                Divider()
                    .opacity(0.5)
                CodeBlockBody(
                    source: source,
                    language: language,
                    showLineNumbers: showLineNumbers,
                    theme: theme
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
    let showLineNumbers: Bool
    let theme: MarkdownTheme

    private var lines: [String] {
        source.components(separatedBy: "\n")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                if showLineNumbers {
                    LineNumberGutter(
                        count: lines.count,
                        font: theme.codeFont
                    )
                    Rectangle()
                        .fill(JinSemanticColor.borderSubtle)
                        .frame(width: 1)
                        .padding(.vertical, 6)
                }
                HighlightedCodeView(
                    source: source,
                    language: language,
                    theme: theme
                )
            }
        }
    }
}

private struct HighlightedCodeView: NSViewRepresentable {
    let source: String
    let language: String?
    let theme: MarkdownTheme

    func makeNSView(context: Context) -> JinMessageTextView {
        let view = JinMessageTextView()
        view.isSelectable = true
        applyAttributedString(to: view)
        return view
    }

    func updateNSView(_ nsView: JinMessageTextView, context: Context) {
        applyAttributedString(to: nsView)
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

    private func applyAttributedString(to view: JinMessageTextView) {
        let highlighted = MarkdownSyntaxHighlighter.highlight(source, language: language, theme: theme)
        let withInsets = NSMutableAttributedString(attributedString: highlighted)
        withInsets.addAttribute(
            .paragraphStyle,
            value: theme.codeParagraphStyle,
            range: NSRange(location: 0, length: withInsets.length)
        )
        view.textStorage?.setAttributedString(withInsets)
        view.textContainerInset = NSSize(width: 14, height: 10)
    }
}

private struct LineNumberGutter: View {
    let count: Int
    let font: NSFont

    var body: some View {
        Text(
            (1...max(1, count))
                .map(String.init)
                .joined(separator: "\n")
        )
        .font(Font(font))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.trailing)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minWidth: 32, alignment: .trailing)
    }
}
