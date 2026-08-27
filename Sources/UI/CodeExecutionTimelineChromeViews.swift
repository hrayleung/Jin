import SwiftUI

struct CodeExecutionTimelineHeaderRow: View {
    let title: String
    let headerStatus: CodeExecutionTimelineSupport.HeaderStatus?
    let collapsedPreview: String?
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.xSmall) {
            headerButton

            if let collapsedPreview {
                Text(collapsedPreview)
                    .font(.caption)
                    .foregroundStyle(JinSemanticColor.textTertiary)
                    .lineLimit(1)
                    .padding(.leading, 24)
            }
        }
    }

    private var headerButton: some View {
        Button(action: onToggle) {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .frame(width: 16, height: 16)
                    .opacity(0.85)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(JinSemanticColor.textSecondary)
                    .lineLimit(1)

                quietStatus

                Spacer(minLength: 0)

                JinDisclosureChevron(
                    isExpanded: isExpanded,
                    font: .caption2.weight(.semibold),
                    foregroundStyle: JinSemanticColor.textTertiary
                )
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(isHovering ? JinSemanticColor.subtleSurface.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hides execution details" : "Shows execution details"))
    }

    @ViewBuilder
    private var quietStatus: some View {
        if let headerStatus {
            HStack(spacing: 4) {
                if let icon = headerStatus.icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor(for: headerStatus.kind))
                }

                if let text = headerStatus.text {
                    Text(text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            headerStatus.kind == .running
                                ? JinSemanticColor.textSecondary
                                : statusColor(for: headerStatus.kind)
                        )
                }
            }
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }

    private func statusColor(for kind: CodeExecutionTimelineSupport.HeaderStatus.Kind) -> Color {
        switch kind {
        case .running:
            return JinSemanticColor.textSecondary
        case .success:
            return ToolTimelinePresentationSupport.StatusTone.success.emphasizedColor
        case .failure:
            return ToolTimelinePresentationSupport.StatusTone.failure.emphasizedColor
        }
    }

    private var accessibilityLabelText: String {
        var parts = [title]
        if let headerStatus {
            switch headerStatus.kind {
            case .running:
                parts.append(headerStatus.text ?? "Running")
            case .success:
                parts.append("Succeeded")
            case .failure:
                parts.append(headerStatus.text ?? "Failed")
            }
        }
        return parts.joined(separator: ", ")
    }
}

struct CodeExecutionTimelineExpandedContentView: View {
    let activities: [CodeExecutionActivity]
    let isSingleExecution: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                CodeExecutionEntryView(
                    activity: activity,
                    entryIndex: index,
                    showsHeader: !isSingleExecution
                )
            }
        }
        .padding(.leading, 24)
        .padding(.top, 2)
        .padding(.bottom, JinSpacing.xSmall)
    }
}
