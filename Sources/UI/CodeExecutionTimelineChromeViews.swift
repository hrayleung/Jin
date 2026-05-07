import SwiftUI

struct CodeExecutionTimelineHeaderRow: View {
    let title: String
    let isStreaming: Bool
    let hasActiveExecution: Bool
    let compactStatus: ToolTimelinePresentationSupport.CompactStatusStyle?
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            headerContent
        }
        .buttonStyle(.plain)
    }

    private var headerContent: some View {
        HStack(spacing: JinSpacing.small) {
            timelineIcon
            titleText

            Spacer(minLength: 0)

            streamingIndicator
            compactStatusBadge
            disclosureIndicator
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var timelineIcon: some View {
        Image(systemName: "chevron.left.forwardslash.chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if isStreaming, hasActiveExecution {
            ProgressView()
                .scaleEffect(0.5)
        }
    }

    @ViewBuilder
    private var compactStatusBadge: some View {
        if let compactStatus {
            ToolTimelinePresentationSupport.CompactStatusBadge(
                style: compactStatus,
                variant: .inline
            )
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

struct CodeExecutionTimelineExpandedContentView: View {
    let activities: [CodeExecutionActivity]

    var body: some View {
        entriesList
            .padding(.horizontal, JinSpacing.small)
            .padding(.top, JinSpacing.xSmall)
            .padding(.bottom, JinSpacing.xSmall)
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                CodeExecutionEntryView(
                    activity: activity,
                    entryIndex: index,
                    showsConnectorAbove: index > 0,
                    showsConnectorBelow: index < activities.count - 1
                )
            }
        }
    }
}
