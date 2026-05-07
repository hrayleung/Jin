import SwiftUI
import SwiftData

struct MCPToolTimelineView: View {
    let toolCalls: [ToolCall]
    let toolResultsByCallID: [String: ToolResult]
    let isStreaming: Bool

    @Query(sort: \MCPServerConfigEntity.name) private var configuredServers: [MCPServerConfigEntity]
    @State private var isExpanded = false

    init(
        toolCalls: [ToolCall],
        toolResultsByCallID: [String: ToolResult],
        isStreaming: Bool
    ) {
        self.toolCalls = toolCalls
        self.toolResultsByCallID = toolResultsByCallID
        self.isStreaming = isStreaming
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                collapsedSummaryRow

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipped()
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.spring(duration: 0.25, bounce: 0), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: entryAnimationSignature)
            .onAppear {
                if isStreaming {
                    isExpanded = true
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                guard streaming else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0)) {
                    isExpanded = true
                }
            }
        }
    }

    // MARK: - Subviews

    private var collapsedSummaryRow: some View {
        MCPToolTimelineCollapsedSummaryRow(
            title: collapsedTitle,
            serverIDs: serverIDs,
            iconIDByServerID: iconIDByServerID,
            isStreaming: isStreaming,
            runningCount: runningCount,
            compactStatusBadges: compactStatusBadges,
            isExpanded: $isExpanded
        )
    }

    private var expandedPanel: some View {
        MCPToolTimelineExpandedPanelView(
            title: expandedTitle,
            statusSummaryText: statusSummaryText,
            serverIDs: serverIDs,
            showsServerSummaryRow: shouldShowServerSummaryRow,
            entries: entries,
            showsPerCallServerTag: shouldShowPerCallServerTag
        )
    }

    // MARK: - Derived Content

    private var entries: [MCPToolTimelineSupport.Entry] {
        MCPToolTimelineSupport.entries(
            toolCalls: toolCalls,
            toolResultsByCallID: toolResultsByCallID
        )
    }

    private var statusCounts: MCPToolTimelineSupport.StatusCounts {
        MCPToolTimelineSupport.counts(for: entries)
    }

    private var runningCount: Int {
        statusCounts.running
    }

    private var serverIDs: [String] {
        MCPToolTimelineSupport.serverIDs(for: entries)
    }

    private var shouldShowServerSummaryRow: Bool {
        MCPToolTimelineSupport.shouldShowServerSummaryRow(for: serverIDs)
    }

    private var shouldShowPerCallServerTag: Bool {
        MCPToolTimelineSupport.shouldShowPerCallServerTag(for: serverIDs)
    }

    private var iconIDByServerID: [String: String] {
        Dictionary(uniqueKeysWithValues: configuredServers.map { server in
            (server.id, server.resolvedMCPIconID)
        })
    }

    private var collapsedTitle: String {
        MCPToolTimelineSupport.collapsedTitle(for: entries, serverIDs: serverIDs)
    }

    private var expandedTitle: String {
        MCPToolTimelineSupport.expandedTitle(for: entries, serverIDs: serverIDs)
    }

    private var compactStatusBadges: [MCPToolTimelineSupport.CompactStatusBadge] {
        MCPToolTimelineSupport.compactStatusBadges(for: entries)
    }

    private var statusSummaryText: String? {
        MCPToolTimelineSupport.statusSummaryText(for: entries)
    }

    private var entryAnimationSignature: String {
        MCPToolTimelineSupport.entryAnimationSignature(for: entries)
    }

}
