import SwiftUI
import AppKit

// MARK: - Content Blocks

struct CodeExecContentBlockView: View {
    let title: String
    let text: String
    let style: CodeExecContentBlockStyle
    let badgeText: String?

    private let lineCount: Int
    private let longestLineLength: Int
    private let highlightedCode: AttributedString?
    private let collapsedHeight: CGFloat = 176
    private let expandedHeight: CGFloat = 320

    @State private var isExpanded = false
    @State private var scrollViewWidth: CGFloat = 0

    init(
        title: String,
        text: String,
        style: CodeExecContentBlockStyle,
        badgeText: String? = nil,
        language: CodeExecCodeLanguage? = nil
    ) {
        self.title = title
        self.text = text
        self.style = style
        self.badgeText = badgeText

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        self.lineCount = max(lines.count, 1)
        self.longestLineLength = lines.map(\.count).max() ?? text.count

        if style.usesSyntaxHighlighting {
            self.highlightedCode = CodeExecSyntaxHighlighter.highlighted(text, language: language)
        } else {
            self.highlightedCode = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: style.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.iconColor)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.titleColor)

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .jinTagStyle(foreground: style.badgeColor)
                }

                Spacer(minLength: 0)

                if showsExpandControl {
                    Button(isExpanded ? "Show Less" : "Show More") {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                CopyToPasteboardButton(
                    text: text,
                    helpText: "Copy \(title.lowercased())",
                    copiedHelpText: "\(title) copied",
                    useProminentStyle: false
                )
            }
            .padding(.horizontal, JinSpacing.medium - 2)
            .padding(.vertical, JinSpacing.xSmall)
            .background(style.headerBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(JinSemanticColor.separator.opacity(0.55))
                    .frame(height: JinStrokeWidth.hairline)
            }

            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                HStack(alignment: .top, spacing: JinSpacing.medium) {
                    if style.showsLineNumbers, let lineNumberText {
                        Text(lineNumberText)
                            .font(Self.contentFont)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.trailing)
                            .padding(.trailing, JinSpacing.small)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(JinSemanticColor.separator.opacity(0.45))
                                    .frame(width: JinStrokeWidth.hairline)
                            }
                    }

                    renderedTextBody
                }
                .padding(.horizontal, JinSpacing.medium - 2)
                .padding(.vertical, JinSpacing.small)
                .frame(minWidth: scrollViewWidth, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { scrollViewWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in scrollViewWidth = w }
                }
            )
            .frame(maxHeight: currentMaxHeight, alignment: .top)
            .background(style.bodyBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                .stroke(style.borderColor, lineWidth: JinStrokeWidth.hairline)
        )
    }

    @ViewBuilder
    private var renderedTextBody: some View {
        if let highlightedCode {
            Text(highlightedCode)
                .font(Self.contentFont)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        } else {
            Text(text)
                .font(Self.contentFont)
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var showsExpandControl: Bool {
        lineCount > 12 || longestLineLength > 120 || text.count > 800
    }

    private var currentMaxHeight: CGFloat? {
        guard showsExpandControl else { return nil }
        return isExpanded ? expandedHeight : collapsedHeight
    }

    private var lineNumberText: String? {
        guard lineCount > 1, lineCount <= 400 else { return nil }
        return (1...lineCount).map(String.init).joined(separator: "\n")
    }

    private static let contentFont = Font.system(.caption, design: .monospaced)
}

struct CodeExecContentBlockStyle {
    let iconName: String
    let iconColor: Color
    let titleColor: Color
    let badgeColor: Color
    let textColor: Color
    let headerBackground: Color
    let bodyBackground: Color
    let borderColor: Color
    let showsLineNumbers: Bool
    let usesSyntaxHighlighting: Bool

    static let code = CodeExecContentBlockStyle(
        iconName: "chevron.left.forwardslash.chevron.right",
        iconColor: .secondary.opacity(0.75),
        titleColor: .secondary,
        badgeColor: .secondary,
        textColor: .primary.opacity(0.88),
        headerBackground: JinSemanticColor.subtleSurfaceStrong,
        bodyBackground: JinSemanticColor.raisedSurface,
        borderColor: JinSemanticColor.separator.opacity(0.75),
        showsLineNumbers: true,
        usesSyntaxHighlighting: true
    )

    static let output = CodeExecContentBlockStyle(
        iconName: "terminal",
        iconColor: .secondary.opacity(0.75),
        titleColor: .secondary,
        badgeColor: .secondary,
        textColor: .secondary,
        headerBackground: JinSemanticColor.subtleSurfaceStrong,
        bodyBackground: JinSemanticColor.raisedSurface,
        borderColor: JinSemanticColor.separator.opacity(0.75),
        showsLineNumbers: false,
        usesSyntaxHighlighting: false
    )

    static let error = CodeExecContentBlockStyle(
        iconName: "exclamationmark.triangle.fill",
        iconColor: Color(nsColor: .systemOrange).opacity(0.9),
        titleColor: Color(nsColor: .systemOrange).opacity(0.95),
        badgeColor: Color(nsColor: .systemOrange).opacity(0.95),
        textColor: Color(nsColor: .systemOrange).opacity(0.95),
        headerBackground: Color(nsColor: .systemOrange).opacity(0.1),
        bodyBackground: Color(nsColor: .systemOrange).opacity(0.045),
        borderColor: Color(nsColor: .systemOrange).opacity(0.24),
        showsLineNumbers: false,
        usesSyntaxHighlighting: false
    )
}

// MARK: - Code Language

enum CodeExecCodeLanguage: Equatable {
    case python
    case javascript
    case shell
    case swift
    case generic

    var badgeLabel: String {
        switch self {
        case .python:
            return "Python"
        case .javascript:
            return "JavaScript"
        case .shell:
            return "Shell"
        case .swift:
            return "Swift"
        case .generic:
            return "Code"
        }
    }

    static func infer(from code: String) -> CodeExecCodeLanguage? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercase = trimmed.lowercased()

        if trimmed.hasPrefix("#!/bin/bash") || trimmed.hasPrefix("#!/bin/sh") || lowercase.contains("echo ") && lowercase.contains("$") {
            return .shell
        }

        if lowercase.contains("import swiftui") || lowercase.contains("struct ") && lowercase.contains(": view") {
            return .swift
        }

        if lowercase.contains("console.log") || lowercase.contains("const ") || lowercase.contains("let ") || lowercase.contains("=>") {
            return .javascript
        }

        if lowercase.contains("import ") || lowercase.contains("print(") || lowercase.contains("def ") || lowercase.contains("plt.") {
            return .python
        }

        return .generic
    }
}

// MARK: - Syntax Highlighting

enum CodeExecSyntaxHighlighter {
    private static let baseColor = NSColor.labelColor.withAlphaComponent(0.88)
    private static let keywordColor = NSColor.systemBlue.withAlphaComponent(0.9)
    private static let stringColor = NSColor.systemRed.withAlphaComponent(0.86)
    private static let commentColor = NSColor.secondaryLabelColor.withAlphaComponent(0.95)
    private static let numberColor = NSColor.systemPurple.withAlphaComponent(0.82)
    private static let functionColor = NSColor.systemTeal.withAlphaComponent(0.9)

    static func highlighted(_ text: String, language: CodeExecCodeLanguage?) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }
        guard text.count <= 20_000 else { return AttributedString(text) }

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .foregroundColor: baseColor
            ]
        )
        let fullRange = NSRange(location: 0, length: attributed.length)

        let functionPattern = #"(?m)\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#
        apply(pattern: functionPattern, color: functionColor, to: attributed, range: fullRange)

        let keywordPattern = keywordPattern(for: language)
        apply(pattern: keywordPattern, color: keywordColor, to: attributed, range: fullRange)

        let numberPattern = #"(?<![\w.])\d+(?:\.\d+)?(?![\w.])"#
        apply(pattern: numberPattern, color: numberColor, to: attributed, range: fullRange)

        let stringPattern = #"(?s)\"\"\".*?\"\"\"|'''.*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
        apply(pattern: stringPattern, color: stringColor, to: attributed, range: fullRange)

        let commentPattern = commentPattern(for: language)
        apply(pattern: commentPattern, color: commentColor, to: attributed, range: fullRange)

        return AttributedString(attributed)
    }

    private static func keywordPattern(for language: CodeExecCodeLanguage?) -> String {
        switch language {
        case .javascript:
            return #"\b(await|async|break|case|catch|class|const|continue|default|else|export|false|finally|for|from|function|if|import|in|let|new|null|return|switch|throw|true|try|typeof|undefined|var|while)\b"#
        case .shell:
            return #"\b(case|do|done|elif|else|esac|export|fi|for|function|if|in|local|return|then|unset|while)\b"#
        case .swift:
            return #"\b(actor|async|await|case|class|enum|extension|false|for|func|if|import|in|let|nil|private|protocol|return|self|struct|switch|throw|true|var|while)\b"#
        case .python, .generic, .none:
            return #"\b(and|as|assert|break|class|continue|def|del|elif|else|except|False|finally|for|from|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#
        }
    }

    private static func commentPattern(for language: CodeExecCodeLanguage?) -> String {
        switch language {
        case .javascript, .swift:
            return #"(?m)//.*$|/\*[\s\S]*?\*/"#
        case .shell, .python, .generic, .none:
            return #"(?m)#.*$"#
        }
    }

    private static func apply(
        pattern: String,
        color: NSColor,
        to attributed: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: attributed.string, options: [], range: range)
        for match in matches {
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
