import SwiftUI

/// Code execution activity in the message timeline.
///
/// Design (Claude / Cursor progressive-disclosure):
/// - **Secondary visual weight** — muted chrome that never competes with prose.
/// - **Single-execution path** is one control (no nested "Execution 1" headers).
/// - **Multi-execution path** uses a quiet summary + compact per-run rows.
/// - Code wraps; never dual-axis scroll (that overflowed the card).
struct CodeExecutionTimelineView: View {
    let activities: [CodeExecutionActivity]
    let isStreaming: Bool
    var onExpansionChanged: () -> Void = {}

    @State private var isExpanded: Bool
    /// Expanded execution details stay unmounted until first expand when the
    /// display mode starts collapsed.
    @State private var hasEverExpanded: Bool
    @State private var expandGeneration = 0

    init(
        activities: [CodeExecutionActivity],
        isStreaming: Bool,
        onExpansionChanged: @escaping () -> Void = {}
    ) {
        self.activities = activities
        self.isStreaming = isStreaming
        self.onExpansionChanged = onExpansionChanged
        let mode = Self.resolveDisplayMode()
        let initiallyExpanded = CodeExecutionTimelineSupport.initialExpansion(
            isStreaming: isStreaming,
            displayMode: mode
        )
        _isExpanded = State(initialValue: initiallyExpanded)
        _hasEverExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CodeExecutionTimelineHeaderRow(
                    title: headerTitle,
                    headerStatus: headerStatus,
                    collapsedPreview: isExpanded ? nil : collapsedPreview,
                    isExpanded: isExpanded,
                    onToggle: toggleExpanded
                )

                if hasEverExpanded {
                    JinCollapsibleContent(isExpanded: isExpanded) {
                        CodeExecutionTimelineExpandedContentView(
                            activities: activities,
                            isSingleExecution: isSingleExecution
                        )
                    }
                }
            }
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: animationSignature)
            .onChange(of: isStreaming) { _, streaming in
                let mode = Self.resolveDisplayMode()
                if let shouldExpand = CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                    isStreaming: streaming,
                    displayMode: mode
                ) {
                    if shouldExpand {
                        hasEverExpanded = true
                    }
                    withAnimation(JinMotion.disclosure(expanding: shouldExpand)) {
                        isExpanded = shouldExpand
                    }
                }
            }
            .onChange(of: isExpanded) { _, _ in
                onExpansionChanged()
            }
        }
    }

    private static func resolveDisplayMode() -> CodeExecutionDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.codeExecutionDisplayMode) ?? ""
        return CodeExecutionDisplayMode(rawValue: raw) ?? .expanded
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

        // First expand: mount collapsed so the height probe warms,
        // then open on the next turns (matches MCP / web search).
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

    private var isSingleExecution: Bool {
        CodeExecutionTimelineSupport.isSingleExecution(activities)
    }

    private var headerTitle: String {
        CodeExecutionTimelineSupport.headerTitle(activityCount: activities.count)
    }

    private var headerStatus: CodeExecutionTimelineSupport.HeaderStatus? {
        CodeExecutionTimelineSupport.headerStatus(for: activities)
    }

    private var collapsedPreview: String? {
        CodeExecutionTimelineSupport.collapsedPreview(for: activities)
    }

    private var animationSignature: String {
        CodeExecutionTimelineSupport.animationSignature(for: activities)
    }
}
