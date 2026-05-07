import SwiftUI

// MARK: - AgentToolTimelineView

struct AgentToolTimelineView: View {
    let activities: [CodexToolActivity]
    let isStreaming: Bool

    @State private var isExpanded: Bool

    init(activities: [CodexToolActivity], isStreaming: Bool) {
        self.activities = activities
        self.isStreaming = isStreaming
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(
            initialValue: AgentToolTimelineSupport.initialExpansion(
                isStreaming: isStreaming,
                displayMode: mode
            )
        )
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                collapsedSummaryRow

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedPanel
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .clipped()
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.spring(duration: 0.3, bounce: 0.05), value: isExpanded)
            .animation(.easeInOut(duration: 0.25), value: entryAnimationSignature)
            .onChange(of: isStreaming) { _, streaming in
                let mode = Self.resolveDisplayMode()
                if let shouldExpand = AgentToolTimelineSupport.shouldExpandAfterStreamingChange(
                    isStreaming: streaming,
                    displayMode: mode
                ) {
                    withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                        isExpanded = shouldExpand
                    }
                }
            }
        }
    }

    private static func resolveDisplayMode() -> AgentToolDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.agentToolDisplayMode) ?? ""
        return AgentToolTimelineSupport.displayMode(rawValue: raw)
    }

    // MARK: - Collapsed Summary Row

    private var collapsedSummaryRow: some View {
        AgentToolTimelineCollapsedSummaryRow(
            title: collapsedTitle,
            isStreaming: isStreaming,
            runningCount: runningCount,
            compactStatus: compactStatus,
            isExpanded: $isExpanded
        )
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        AgentToolTimelineExpandedPanelView(
            activities: activities,
            isStreaming: isStreaming
        )
    }

    // MARK: - Derived Content

    private var runningCount: Int {
        AgentToolTimelineSupport.counts(for: activities).running
    }

    private var collapsedTitle: String {
        AgentToolTimelineSupport.collapsedTitle(for: activities)
    }

    private var compactStatus: ToolTimelinePresentationSupport.CompactStatusStyle? {
        AgentToolTimelineSupport.compactStatus(for: activities)
            .map(ToolTimelinePresentationSupport.CompactStatusStyle.init)
    }

    private var entryAnimationSignature: String {
        AgentToolTimelineSupport.entryAnimationSignature(for: activities)
    }
}
