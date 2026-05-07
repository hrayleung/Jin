import SwiftUI

struct ContextUsageIndicatorView: View, Equatable {
    let estimate: ChatContextUsageEstimate
    var modelName: String? = nil

    @State private var isPopoverPresented = false

    static func == (lhs: ContextUsageIndicatorView, rhs: ContextUsageIndicatorView) -> Bool {
        lhs.estimate == rhs.estimate && lhs.modelName == rhs.modelName
    }

    static func summaryText(for estimate: ChatContextUsageEstimate) -> String {
        ContextUsageIndicatorSupport.summaryText(for: estimate)
    }

    static func percentageText(for estimate: ChatContextUsageEstimate) -> String {
        ContextUsageIndicatorSupport.percentageText(for: estimate)
    }

    static func compactTokenCount(_ value: Int) -> String {
        ContextUsageIndicatorSupport.compactTokenCount(value)
    }

    private enum Severity {
        init(_ supportSeverity: ContextUsageIndicatorSupport.Severity) {
            switch supportSeverity {
            case .normal:
                self = .normal
            case .warning:
                self = .warning
            case .critical:
                self = .critical
            }
        }

        case normal
        case warning
        case critical
    }

    private var presentation: ContextUsageIndicatorSupport.Presentation {
        ContextUsageIndicatorSupport.Presentation(
            estimate: estimate,
            modelName: modelName
        )
    }

    private var severity: Severity {
        Severity(presentation.severity)
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
        presentation.percentageText
    }

    private var summaryText: String {
        presentation.summaryText
    }

    private var displayedFraction: CGFloat {
        CGFloat(presentation.displayedFraction)
    }

    private var titleText: String {
        presentation.titleText
    }

    private var usageLine: String {
        presentation.usageLine
    }

    private var reserveLine: String {
        presentation.reserveLine
    }

    private var truncationLine: String? {
        presentation.truncationLine
    }

    private var helpText: String {
        presentation.helpText
    }

    private var accessibilityValueText: String {
        presentation.accessibilityValueText
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
