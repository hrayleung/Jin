import SwiftUI

struct CodexToolTimelineCollapsedSummaryRow: View {
    let title: String
    let isStreaming: Bool
    let runningCount: Int
    let compactStatusStyle: ToolTimelinePresentationSupport.CompactStatusStyle?
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                isExpanded.toggle()
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: JinSpacing.small) {
            leadingIcon

            titleText

            Spacer(minLength: 0)

            activityIndicators

            disclosureIndicator
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var leadingIcon: some View {
        ZStack {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 18, height: 18)
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var activityIndicators: some View {
        if isStreaming, runningCount > 0 {
            ToolTimelinePresentationSupport.RunningIndicator()
        }

        if let compactStatusStyle {
            ToolTimelinePresentationSupport.CompactStatusBadge(style: compactStatusStyle)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.spring(duration: 0.25, bounce: 0.15), value: isExpanded)
    }
}

struct CodexToolTimelineExpandedPanelView: View {
    let title: String
    let statusSummaryText: String?
    let entries: [CodexToolTimelineSupport.Entry]
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small + 2) {
            header

            entriesList
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall + 2)
        .padding(.bottom, JinSpacing.small)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            Text(title)
                .font(.headline)

            statusSummary

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusSummary: some View {
        if let statusSummaryText {
            Text(statusSummaryText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                entryRow(index: index, entry: entry)
            }
        }
    }

    private func entryRow(
        index: Int,
        entry: CodexToolTimelineSupport.Entry
    ) -> some View {
        CodexToolEntryView(
            entry: entry,
            entryIndex: index,
            showsConnectorAbove: index > 0,
            showsConnectorBelow: index < entries.count - 1,
            isStreaming: isStreaming
        )
    }
}
