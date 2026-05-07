import SwiftUI

// MARK: - Content Blocks

struct CodeExecContentBlockView: View {
    let title: String
    let text: String
    let style: CodeExecContentBlockStyle
    let badgeText: String?

    private let contentMetrics: CodeExecContentBlockSupport.Metrics
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
        self.contentMetrics = CodeExecContentBlockSupport.metrics(for: text)

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
        CodeExecContentBlockSupport.showsExpandControl(for: contentMetrics)
    }

    private var currentMaxHeight: CGFloat? {
        CodeExecContentBlockSupport.currentMaxHeight(
            for: contentMetrics,
            isExpanded: isExpanded,
            collapsedHeight: collapsedHeight,
            expandedHeight: expandedHeight
        )
    }

    private var lineNumberText: String? {
        CodeExecContentBlockSupport.lineNumberText(forLineCount: contentMetrics.lineCount)
    }

    private static let contentFont = Font.system(.caption, design: .monospaced)
}
