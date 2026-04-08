import SwiftUI

struct ContextUsageIndicatorView: View, Equatable {
    let estimate: ChatContextUsageEstimate
    var modelName: String? = nil

    @State private var isPopoverPresented = false

    static func == (lhs: ContextUsageIndicatorView, rhs: ContextUsageIndicatorView) -> Bool {
        lhs.estimate == rhs.estimate && lhs.modelName == rhs.modelName
    }

    static func summaryText(for estimate: ChatContextUsageEstimate) -> String {
        "\(percentageText(for: estimate)) · \(compactTokenCount(estimate.inputTokens)) / \(compactTokenCount(max(estimate.contextWindow, 0))) context used"
    }

    static func percentageText(for estimate: ChatContextUsageEstimate) -> String {
        let value = estimate.clampedUsageFraction * 100
        return "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    static func compactTokenCount(_ value: Int) -> String {
        let absoluteValue = abs(value)

        if absoluteValue >= 1_000_000 {
            return "\((Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
        }

        if absoluteValue >= 1_000 {
            return "\((Double(value) / 1_000).formatted(.number.precision(.fractionLength(1))))K"
        }

        return "\(value)"
    }

    private enum Severity {
        case normal
        case warning
        case critical
    }

    private var severity: Severity {
        if estimate.didTruncateHistory || estimate.clampedUsageFraction >= 0.9 {
            return .critical
        }
        if estimate.clampedUsageFraction >= 0.75 {
            return .warning
        }
        return .normal
    }

    private var progressColor: Color {
        switch severity {
        case .normal:
            return .accentColor
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var labelColor: Color {
        switch severity {
        case .normal:
            return .secondary
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var percentageText: String {
        Self.percentageText(for: estimate)
    }

    private var summaryText: String {
        Self.summaryText(for: estimate)
    }

    private var displayedFraction: CGFloat {
        let fraction = CGFloat(estimate.clampedUsageFraction)
        if estimate.inputTokens > 0 {
            return max(fraction, 0.025)
        }
        return fraction
    }

    private var titleText: String {
        if let modelName, !modelName.isEmpty {
            return "\(modelName) context usage"
        }
        return "Current model context usage"
    }

    private var usageLine: String {
        let inputTokens = estimate.inputTokens.formatted(.number.grouping(.automatic))
        let availableTokens = estimate.availableInputTokens.formatted(.number.grouping(.automatic))
        return "\(inputTokens) of \(availableTokens) input tokens used"
    }

    private var reserveLine: String {
        let reservedTokens = estimate.reservedOutputTokens.formatted(.number.grouping(.automatic))
        let contextWindow = estimate.contextWindow.formatted(.number.grouping(.automatic))
        return "\(reservedTokens) reserved for output from a \(contextWindow)-token context window"
    }

    private var truncationLine: String? {
        guard estimate.didTruncateHistory else { return nil }
        let tokenCount = estimate.truncatedInputTokens.formatted(.number.grouping(.automatic))
        let messageCount = estimate.truncatedMessageCount.formatted(.number.grouping(.automatic))
        return "Older history trimmed: \(messageCount) messages, about \(tokenCount) tokens"
    }

    private var helpText: String {
        var lines = [summaryText, usageLine, reserveLine]
        if let truncationLine {
            lines.append(truncationLine)
        }
        return lines.joined(separator: "\n")
    }

    private var accessibilityValueText: String {
        var parts = ["\(percentageText) used", usageLine]
        if let truncationLine {
            parts.append(truncationLine)
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: 2)

                    Circle()
                        .trim(from: 0, to: displayedFraction)
                        .stroke(
                            progressColor,
                            style: StrokeStyle(lineWidth: 2.25, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)

                Text(percentageText)
                    .font(.callout.weight(severity == .normal ? .medium : .semibold))
                    .foregroundStyle(labelColor)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            contextUsagePopover
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titleText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Shows current context usage. Click to view details.")
    }

    private var contextUsagePopover: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            if let modelName, !modelName.isEmpty {
                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(summaryText)
                .font(.callout.weight(.semibold))
                .monospacedDigit()

            Text(usageLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(reserveLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let truncationLine {
                Text(truncationLine)
                    .font(.caption)
                    .foregroundStyle(severity == .critical ? .red : .secondary)
            }
        }
        .padding(JinSpacing.medium)
        .frame(minWidth: 260, alignment: .leading)
    }
}
