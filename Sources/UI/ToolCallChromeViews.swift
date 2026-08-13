import SwiftUI

struct ToolCallHeaderRow: View {
    let serverLabel: String
    let toolLabel: String
    let showsServerTag: Bool
    let status: ToolCallExecutionStatus
    let statusLabel: String
    let durationText: String?
    let statusStyle: ToolTimelinePresentationSupport.StatusVisualStyle
    let isExpanded: Bool
    /// Quieter typography for multi-tool lists inside MCP.
    var quiet: Bool = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: JinSpacing.small) {
                if showsServerTag {
                    Text(serverLabel)
                        .jinTagStyle()
                }

                Text(toolLabel)
                    .font(
                        quiet
                            ? .system(.caption, design: .default).weight(.medium)
                            : .system(.caption, design: .monospaced).weight(.semibold)
                    )
                    .foregroundStyle(quiet ? JinSemanticColor.textSecondary : .primary)
                    .lineLimit(1)

                quietStatusCluster

                Spacer(minLength: 0)

                JinDisclosureChevron(
                    isExpanded: isExpanded,
                    font: .caption2.weight(.semibold),
                    foregroundStyle: JinSemanticColor.textTertiary
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hides tool output" : "Shows tool output"))
    }

    private var quietStatusCluster: some View {
        HStack(spacing: 4) {
            Image(systemName: glyphName)
                .font(.system(size: quiet ? 10 : 11, weight: .semibold))
                .foregroundStyle(statusStyle.accent)

            if !statusLabel.isEmpty {
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusStyle.text)
            }

            if let durationText, status != .running {
                Text(durationText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(JinSemanticColor.textTertiary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var glyphName: String {
        switch status {
        case .running: return "circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var accessibilityLabelText: String {
        var parts = [toolLabel]
        if showsServerTag {
            parts.insert(serverLabel, at: 0)
        }
        if !statusLabel.isEmpty {
            parts.append(statusLabel)
        } else {
            switch status {
            case .running: parts.append("Running")
            case .success: parts.append("Succeeded")
            case .error: parts.append("Failed")
            }
        }
        if let durationText, status != .running {
            parts.append(durationText)
        }
        return parts.joined(separator: ", ")
    }
}

struct ToolCallArgumentSummaryView: View {
    let argumentSummary: String

    var body: some View {
        Text(argumentSummary)
            .font(.caption)
            .foregroundStyle(JinSemanticColor.textTertiary)
            .lineLimit(2)
            .textSelection(.enabled)
    }
}

struct ToolCallExpandedContentView: View {
    let formattedArgumentsJSON: String?
    let toolResult: ToolResult?
    let signature: String?

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ToolCallCodeBlockView(
                title: "Arguments",
                text: formattedArgumentsJSON ?? "{}",
                showsCopyButton: true
            )

            if let toolResult {
                ToolCallCodeBlockView(
                    title: toolResult.isError ? "Error" : "Output",
                    text: toolResult.content,
                    showsCopyButton: true,
                    isError: toolResult.isError
                )

                if let rawOutputPath = toolResult.rawOutputPath {
                    ToolOutputFileActionRowView(rawOutputPath: rawOutputPath)
                }
            }

            if let signature, !signature.isEmpty {
                ToolCallCodeBlockView(title: "Signature", text: signature)
            }
        }
    }
}

struct ToolCallCodeBlockView: View {
    private static let maxContentHeight: CGFloat = 160
    private static let minContentHeight: CGFloat = 40
    private static let lineHeight: CGFloat = 15
    private static let verticalPadding: CGFloat = 14
    private static let displayCharacterCap = 4_000

    let title: String
    let text: String
    var showsCopyButton: Bool = false
    var isError: Bool = false

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            codeContent
            if isOverflowing {
                Text("Scroll for more · copy for full output")
                    .font(.caption2)
                    .foregroundStyle(JinSemanticColor.textTertiary)
            }
        }
        // Hover covers header + content so the copy button brightens when
        // the pointer is on it (not only when over the body text).
        .onHover { isHovering = $0 }
    }

    private var sectionHeader: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isError ? Color.orange.opacity(0.9) : JinSemanticColor.textTertiary)

            if showsCopyButton {
                CopyToPasteboardButton(
                    text: text,
                    helpText: "Copy \(title.lowercased())",
                    copiedHelpText: "\(title) copied",
                    useProminentStyle: false
                )
                .opacity(isHovering ? 1 : 0.35)
                .animation(JinMotion.hover, value: isHovering)
            }

            Spacer(minLength: 0)
        }
    }

    private var codeContent: some View {
        // Fixed-size shell reports a finite height to `JinCollapsibleContent`'s
        // `fixedSize` probe. ScrollView is an overlay so its ideal content
        // height cannot leak into the curtain measurement (the original
        // residual-gray bug).
        Color.clear
            .frame(height: adaptiveHeight)
            .overlay {
                ScrollView(.vertical, showsIndicators: isOverflowing) {
                    Text(displayText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(JinSemanticColor.textSecondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, JinSpacing.small)
                        .padding(.vertical, JinSpacing.xSmall + 2)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(JinSemanticColor.subtleSurface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(
                        isError
                            ? Color.orange.opacity(0.28)
                            : JinSemanticColor.borderSubtle.opacity(0.8),
                        lineWidth: JinStrokeWidth.hairline
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
    }

    /// Short payloads get a tight window; long ones cap so the timeline stays calm.
    private var adaptiveHeight: CGFloat {
        min(Self.maxContentHeight, max(Self.minContentHeight, estimatedContentHeight))
    }

    private var estimatedContentHeight: CGFloat {
        let lines = max(1, displayText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
        let wrappedExtra = displayText.count > 120 ? displayText.count / 90 : 0
        let estimatedLines = lines + wrappedExtra
        return CGFloat(estimatedLines) * Self.lineHeight + Self.verticalPadding
    }

    private var isOverflowing: Bool {
        estimatedContentHeight > Self.maxContentHeight || text.count > Self.displayCharacterCap
    }

    private var displayText: String {
        guard text.count > Self.displayCharacterCap else { return text }
        let end = text.index(text.startIndex, offsetBy: Self.displayCharacterCap)
        return String(text[..<end]) + "\n… (truncated — copy for full output)"
    }
}
