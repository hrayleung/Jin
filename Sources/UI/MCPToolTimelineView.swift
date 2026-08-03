import SwiftUI
import SwiftData

/// MCP tool activity in the message timeline.
///
/// Design (Claude / Cursor progressive-disclosure):
/// - **Secondary visual weight** — muted chrome that never competes with prose.
/// - **Single-tool path** collapses outer + inner into one control (no nested
///   "MCP · name" then "name Done" double header).
/// - **Multi-tool path** uses a quiet summary + compact per-call rows.
/// - Expand only reveals payload; status/duration stay on the header.
struct MCPToolTimelineView: View {
    let toolCalls: [ToolCall]
    let toolResultsByCallID: [String: ToolResult]
    let isStreaming: Bool
    var onExpansionChanged: () -> Void = {}

    @Query(sort: \MCPServerConfigEntity.name) private var configuredServers: [MCPServerConfigEntity]
    @State private var isExpanded = false
    @State private var hasEverExpanded = false
    @State private var expandGeneration = 0

    init(
        toolCalls: [ToolCall],
        toolResultsByCallID: [String: ToolResult],
        isStreaming: Bool,
        onExpansionChanged: @escaping () -> Void = {}
    ) {
        self.toolCalls = toolCalls
        self.toolResultsByCallID = toolResultsByCallID
        self.isStreaming = isStreaming
        self.onExpansionChanged = onExpansionChanged
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if isSingleTool, let entry = entries.first {
                    singleToolBody(entry: entry)
                } else {
                    multiToolBody
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: entryAnimationSignature)
            .onAppear {
                if isStreaming {
                    openForStreaming()
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                guard streaming else { return }
                openForStreaming()
            }
            .onChange(of: isExpanded) { _, _ in
                onExpansionChanged()
            }
        }
    }

    // MARK: - Single tool (unified control)

    @ViewBuilder
    private func singleToolBody(entry: MCPToolTimelineSupport.Entry) -> some View {
        MCPSingleToolTimelineRow(
            entry: entry,
            iconID: summaryIconID,
            isStreaming: isStreaming,
            isExpanded: isExpanded,
            onToggle: toggleExpanded
        )
        .onAppear {
            // Warm-mount payload while collapsed so first expand has a solid height.
            if !hasEverExpanded {
                hasEverExpanded = true
            }
        }
    }

    // MARK: - Multi tool

    private var multiToolBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            MCPToolTimelineCollapsedSummaryRow(
                title: collapsedTitle,
                serverIDs: serverIDs,
                iconIDByServerID: iconIDByServerID,
                isStreaming: isStreaming,
                runningCount: runningCount,
                compactStatusBadges: compactStatusBadges,
                durationText: totalDurationText,
                isExpanded: isExpanded,
                onToggle: toggleExpanded
            )

            if hasEverExpanded {
                JinCollapsibleContent(isExpanded: isExpanded) {
                    MCPToolTimelineExpandedPanelView(
                        entries: entries,
                        showsPerCallServerTag: shouldShowPerCallServerTag,
                        onEntryExpansionChanged: onExpansionChanged
                    )
                    .padding(.top, JinSpacing.xSmall)
                }
            }
        }
    }

    // MARK: - Expand

    private func openForStreaming() {
        hasEverExpanded = true
        expandGeneration &+= 1
        let generation = expandGeneration
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard generation == expandGeneration else { return }
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
            // Layout invalidation comes from `.onChange(of: isExpanded)` only —
            // an extra call here double-invalidated the parent row.
        }
    }

    private func toggleExpanded() {
        expandGeneration &+= 1
        let generation = expandGeneration

        if isExpanded {
            withAnimation(JinMotion.disclosure(expanding: false)) {
                isExpanded = false
            }
            return
        }

        if hasEverExpanded {
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
            return
        }

        hasEverExpanded = true
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard generation == expandGeneration else { return }
            withAnimation(JinMotion.disclosure(expanding: true)) {
                isExpanded = true
            }
        }
    }

    // MARK: - Derived

    private var entries: [MCPToolTimelineSupport.Entry] {
        MCPToolTimelineSupport.entries(
            toolCalls: toolCalls,
            toolResultsByCallID: toolResultsByCallID
        )
    }

    private var isSingleTool: Bool { entries.count == 1 }

    private var statusCounts: MCPToolTimelineSupport.StatusCounts {
        MCPToolTimelineSupport.counts(for: entries)
    }

    private var runningCount: Int { statusCounts.running }

    private var serverIDs: [String] {
        MCPToolTimelineSupport.serverIDs(for: entries)
    }

    private var shouldShowPerCallServerTag: Bool {
        MCPToolTimelineSupport.shouldShowPerCallServerTag(for: serverIDs)
    }

    private var iconIDByServerID: [String: String] {
        Dictionary(uniqueKeysWithValues: configuredServers.map { server in
            (server.id, server.resolvedMCPIconID)
        })
    }

    private var summaryIconID: String {
        MCPToolTimelineSupport.summaryIconID(
            for: serverIDs,
            iconIDByServerID: iconIDByServerID,
            defaultIconID: MCPIconCatalog.defaultIconID
        )
    }

    private var collapsedTitle: String {
        MCPToolTimelineSupport.collapsedTitle(for: entries, serverIDs: serverIDs)
    }

    private var compactStatusBadges: [MCPToolTimelineSupport.CompactStatusBadge] {
        MCPToolTimelineSupport.compactStatusBadges(for: entries)
    }

    private var totalDurationText: String? {
        MCPToolTimelineSupport.compactDurationText(for: entries)
    }

    private var entryAnimationSignature: String {
        MCPToolTimelineSupport.entryAnimationSignature(for: entries)
    }
}
