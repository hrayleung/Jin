import SwiftUI

// MARK: - CodexToolTimelineView

struct CodexToolTimelineView: View {
    let activities: [CodexToolActivity]
    let isStreaming: Bool

    @State private var isExpanded: Bool

    init(activities: [CodexToolActivity], isStreaming: Bool) {
        self.activities = activities
        self.isStreaming = isStreaming
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(
            initialValue: CodexToolTimelineSupport.initialExpansion(
                isStreaming: isStreaming,
                displayMode: mode
            )
        )
    }

    var body: some View {
        if !entries.isEmpty {
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
                if let shouldExpand = CodexToolTimelineSupport.shouldExpandAfterStreamingChange(
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

    private static func resolveDisplayMode() -> CodexToolDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.codexToolDisplayMode) ?? ""
        return CodexToolTimelineSupport.displayMode(rawValue: raw)
    }

    // MARK: - Collapsed Summary Row

    private var collapsedSummaryRow: some View {
        CodexToolTimelineCollapsedSummaryRow(
            title: collapsedTitle,
            isStreaming: isStreaming,
            runningCount: runningCount,
            compactStatusStyle: compactStatusStyle,
            isExpanded: $isExpanded
        )
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        CodexToolTimelineExpandedPanelView(
            title: entries.count == 1 ? "Codex Tool" : "Codex Tools",
            statusSummaryText: statusSummaryText,
            entries: entries,
            isStreaming: isStreaming
        )
    }

    // MARK: - Derived Content

    private var entries: [CodexToolTimelineSupport.Entry] {
        CodexToolTimelineSupport.entries(for: activities)
    }

    private var activityCounts: CodexToolTimelineSupport.ActivityCounts {
        CodexToolTimelineSupport.counts(for: entries)
    }

    private var runningCount: Int {
        activityCounts.running
    }

    private var collapsedTitle: String {
        CodexToolTimelineSupport.collapsedTitle(for: entries)
    }

    private var compactStatusStyle: ToolTimelinePresentationSupport.CompactStatusStyle? {
        CodexToolTimelineSupport.compactStatus(for: entries)
            .map(ToolTimelinePresentationSupport.CompactStatusStyle.init)
    }

    private var statusSummaryText: String? {
        CodexToolTimelineSupport.statusSummaryText(for: entries)
    }

    private var entryAnimationSignature: String {
        CodexToolTimelineSupport.entryAnimationSignature(for: entries)
    }
}
