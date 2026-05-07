import Foundation

enum ContextUsageIndicatorSupport {
    private enum Constants {
        static let warningUsageFraction = 0.75
        static let criticalUsageFraction = 0.9
        static let minimumVisibleProgressFraction = 0.025
    }

    enum Severity: Equatable {
        case normal
        case warning
        case critical
    }

    struct Presentation: Equatable {
        let severity: Severity
        let percentageText: String
        let summaryText: String
        let displayedFraction: Double
        let titleText: String
        let usageLine: String
        let reserveLine: String
        let truncationLine: String?
        let helpText: String
        let accessibilityValueText: String

        init(estimate: ChatContextUsageEstimate, modelName: String?) {
            severity = ContextUsageIndicatorSupport.severity(for: estimate)
            percentageText = ContextUsageIndicatorSupport.percentageText(for: estimate)
            summaryText = ContextUsageIndicatorSupport.summaryText(for: estimate)
            displayedFraction = ContextUsageIndicatorSupport.displayedFraction(for: estimate)
            titleText = ContextUsageIndicatorSupport.titleText(modelName: modelName)
            usageLine = ContextUsageIndicatorSupport.usageLine(for: estimate)
            reserveLine = ContextUsageIndicatorSupport.reserveLine(for: estimate)
            truncationLine = ContextUsageIndicatorSupport.truncationLine(for: estimate)
            helpText = ContextUsageIndicatorSupport.helpText(
                summaryText: summaryText,
                usageLine: usageLine,
                reserveLine: reserveLine,
                truncationLine: truncationLine
            )
            accessibilityValueText = ContextUsageIndicatorSupport.accessibilityValueText(
                percentageText: percentageText,
                usageLine: usageLine,
                truncationLine: truncationLine
            )
        }
    }

    static func summaryText(for estimate: ChatContextUsageEstimate) -> String {
        "\(percentageText(for: estimate)) · \(compactTokenCount(estimate.inputTokens)) / \(compactTokenCount(max(estimate.contextWindow, 0))) context used"
    }

    static func percentageText(for estimate: ChatContextUsageEstimate) -> String {
        let value = estimate.clampedUsageFraction * 100
        return "\(oneDecimalText(value))%"
    }

    static func compactTokenCount(_ value: Int) -> String {
        let absoluteValue = abs(value)

        if absoluteValue >= 1_000_000 {
            return "\(oneDecimalText(Double(value) / 1_000_000))M"
        }

        if absoluteValue >= 1_000 {
            return "\(oneDecimalText(Double(value) / 1_000))K"
        }

        return "\(value)"
    }

    static func severity(for estimate: ChatContextUsageEstimate) -> Severity {
        if estimate.didTruncateHistory || estimate.clampedUsageFraction >= Constants.criticalUsageFraction {
            return .critical
        }
        if estimate.clampedUsageFraction >= Constants.warningUsageFraction {
            return .warning
        }
        return .normal
    }

    static func displayedFraction(for estimate: ChatContextUsageEstimate) -> Double {
        let fraction = estimate.clampedUsageFraction
        if estimate.inputTokens > 0 {
            return max(fraction, Constants.minimumVisibleProgressFraction)
        }
        return fraction
    }

    static func titleText(modelName: String?) -> String {
        if let modelName, !modelName.isEmpty {
            return "\(modelName) context usage"
        }
        return "Current model context usage"
    }

    static func usageLine(for estimate: ChatContextUsageEstimate) -> String {
        let inputTokens = groupedTokenCount(estimate.inputTokens)
        let availableTokens = groupedTokenCount(estimate.availableInputTokens)
        return "\(inputTokens) of \(availableTokens) input tokens used"
    }

    static func reserveLine(for estimate: ChatContextUsageEstimate) -> String {
        let reservedTokens = groupedTokenCount(estimate.reservedOutputTokens)
        let contextWindow = groupedTokenCount(estimate.contextWindow)
        return "\(reservedTokens) reserved for output from a \(contextWindow)-token context window"
    }

    static func truncationLine(for estimate: ChatContextUsageEstimate) -> String? {
        guard estimate.didTruncateHistory else { return nil }
        let tokenCount = groupedTokenCount(estimate.truncatedInputTokens)
        let messageCount = groupedTokenCount(estimate.truncatedMessageCount)
        return "Older history trimmed: \(messageCount) messages, about \(tokenCount) tokens"
    }

    private static func helpText(
        summaryText: String,
        usageLine: String,
        reserveLine: String,
        truncationLine: String?
    ) -> String {
        var lines = [summaryText, usageLine, reserveLine]
        if let truncationLine {
            lines.append(truncationLine)
        }
        return lines.joined(separator: "\n")
    }

    private static func accessibilityValueText(
        percentageText: String,
        usageLine: String,
        truncationLine: String?
    ) -> String {
        var parts = ["\(percentageText) used", usageLine]
        if let truncationLine {
            parts.append(truncationLine)
        }
        return parts.joined(separator: ", ")
    }

    private static func groupedTokenCount(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func oneDecimalText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
