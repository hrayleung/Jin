import SwiftUI

struct MCPToolTimelineCollapsedSummaryRow: View {
    let title: String
    let serverIDs: [String]
    let iconIDByServerID: [String: String]
    let isStreaming: Bool
    let runningCount: Int
    let compactStatusBadges: [MCPToolTimelineSupport.CompactStatusBadge]
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            summaryRowContent
        }
        .buttonStyle(.plain)
    }

    private var summaryRowContent: some View {
        HStack(spacing: JinSpacing.small) {
            MCPToolTimelineSummaryIconStack(
                serverIDs: serverIDs,
                iconIDByServerID: iconIDByServerID
            )

            titleText

            // Status badges + streaming live next to the title so the eye
            // doesn't have to traverse to the right margin to read state.
            MCPToolTimelineCompactStatusView(badges: compactStatusBadges)

            streamingIndicator

            Spacer(minLength: 0)

            disclosureIndicator
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if isStreaming, runningCount > 0 {
            ProgressView()
                .scaleEffect(0.5)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(JinSemanticColor.textTertiary)
    }
}

private struct MCPToolTimelineSummaryIconStack: View {
    let serverIDs: [String]
    let iconIDByServerID: [String: String]

    var body: some View {
        if serverIDs.count <= 1 {
            MCPIconView(iconID: summaryIconID, fallbackSystemName: "server.rack", size: 14)
                .frame(width: 16, height: 16)
        } else {
            let layout = MCPToolTimelineSupport.iconStackLayout(for: serverIDs)

            ZStack(alignment: .leading) {
                ForEach(Array(layout.displayedServerIDs.enumerated()), id: \.element) { index, serverID in
                    MCPIconView(
                        iconID: resolvedIconID(forServerID: serverID),
                        fallbackSystemName: "server.rack",
                        size: 14
                    )
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(.regularMaterial)
                            .frame(width: 18, height: 18)
                    )
                    .offset(x: CGFloat(layout.overlapOffset) * CGFloat(index))
                    .zIndex(Double(layout.displayedServerIDs.count - index))
                }
            }
            .frame(width: CGFloat(layout.totalWidth), height: 16)
        }
    }

    private var summaryIconID: String {
        MCPToolTimelineSupport.summaryIconID(
            for: serverIDs,
            iconIDByServerID: iconIDByServerID,
            defaultIconID: MCPIconCatalog.defaultIconID
        )
    }

    private func resolvedIconID(forServerID serverID: String) -> String {
        MCPToolTimelineSupport.resolvedIconID(
            forServerID: serverID,
            iconIDByServerID: iconIDByServerID,
            defaultIconID: MCPIconCatalog.defaultIconID
        )
    }
}

private struct MCPToolTimelineCompactStatusView: View {
    let badges: [MCPToolTimelineSupport.CompactStatusBadge]

    var body: some View {
        if !badges.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    MCPToolTimelineCompactStatusBadgeView(
                        badge: badge,
                        showsCount: badge.count > 1 || badges.count > 1
                    )
                }
            }
        }
    }
}

private struct MCPToolTimelineCompactStatusBadgeView: View {
    let badge: MCPToolTimelineSupport.CompactStatusBadge
    let showsCount: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: badge.icon)
                .font(.system(size: 11))

            if showsCount {
                Text("\(badge.count)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(ToolTimelinePresentationSupport.emphasizedCompactStatusColor(for: badge.tone))
    }
}

struct MCPToolTimelineExpandedPanelView: View {
    let title: String
    let statusSummaryText: String?
    let serverIDs: [String]
    let showsServerSummaryRow: Bool
    let entries: [MCPToolTimelineSupport.Entry]
    let showsPerCallServerTag: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            panelHeader
            serverSummaryRow
            entriesList
        }
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.xSmall)
    }

    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small - 2) {
            Text(title)
                .font(.headline)

            statusSummary

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusSummary: some View {
        if let statusSummaryText {
            Text("(\(statusSummaryText))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var serverSummaryRow: some View {
        if showsServerSummaryRow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JinSpacing.xSmall) {
                    ForEach(serverIDs, id: \.self) { serverID in
                        Text(serverID)
                            .jinTagStyle()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ToolCallView(
                    toolCall: entry.call,
                    toolResult: entry.result,
                    showsConnectorAbove: index > 0,
                    showsConnectorBelow: index < entries.count - 1,
                    showsServerTag: showsPerCallServerTag
                )
            }
        }
    }
}
