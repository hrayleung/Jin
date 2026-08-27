import SwiftUI

// MARK: - Content Blocks

struct CodeExecContentBlockView: View {
    let title: String
    let text: String
    let style: CodeExecContentBlockStyle
    let badgeText: String?

    private let contentMetrics: CodeExecContentBlockSupport.Metrics
    private let language: CodeExecCodeLanguage?

    @State private var isExpanded = false

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
        self.language = language
        self.contentMetrics = CodeExecContentBlockSupport.metrics(for: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader

            ZStack(alignment: .bottom) {
                renderedTextBody
                    .padding(.horizontal, JinSpacing.small)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                            .fill(style.bodyBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))

                if showsExpandControl, !isExpanded {
                    LinearGradient(
                        colors: [style.bodyBackground.opacity(0), style.bodyBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 28)
                    .allowsHitTesting(false)
                }
            }

            if showsExpandControl {
                Button(expandTitle) {
                    withAnimation(.spring(duration: 0.25, bounce: 0)) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }

            if isExpanded, let remainderCaption {
                Text(remainderCaption)
                    .font(.caption2)
                    .foregroundStyle(JinSemanticColor.textTertiary)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: style.iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.iconColor)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.titleColor)

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .jinTagStyle(foreground: style.badgeColor)
            }

            Spacer(minLength: 0)

            CopyToPasteboardButton(
                text: text,
                helpText: "Copy \(title.lowercased())",
                copiedHelpText: "\(title) copied",
                useProminentStyle: false
            )
        }
    }

    @ViewBuilder
    private var renderedTextBody: some View {
        if style.usesSyntaxHighlighting {
            Text(CodeExecSyntaxHighlighter.highlighted(visibleText, language: language))
                .font(Self.contentFont)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(visibleText)
                .font(Self.contentFont)
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var showsExpandControl: Bool {
        CodeExecContentBlockSupport.showsExpandControl(for: contentMetrics)
    }

    private var visibleText: String {
        CodeExecContentBlockSupport.visibleText(for: text, isExpanded: isExpanded)
    }

    private var expandTitle: String {
        CodeExecContentBlockSupport.expandControlTitle(
            for: contentMetrics,
            isExpanded: isExpanded
        )
    }

    private var remainderCaption: String? {
        CodeExecContentBlockSupport.truncatedRemainderCaption(for: contentMetrics)
    }

    private static let contentFont = Font.system(.caption, design: .monospaced)
}
