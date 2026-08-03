import SwiftUI

/// Displays a timeline of code execution activities from provider-native code execution tools
/// (OpenAI Code Interpreter, Anthropic Code Execution, xAI Code Interpreter).
struct CodeExecutionTimelineView: View {
    let activities: [CodeExecutionActivity]
    let isStreaming: Bool
    var onExpansionChanged: () -> Void = {}

    @State private var isExpanded: Bool
    /// Expanded execution details stay unmounted until first expand when the
    /// display mode starts collapsed.
    @State private var hasEverExpanded: Bool

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
                headerRow

                if hasEverExpanded {
                    JinCollapsibleContent(isExpanded: isExpanded) {
                        expandedContent
                    }
                }
            }
            .clipped()
            // Height animation is driven only by `withAnimation` on toggle.
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

    // MARK: - Header Row

    private var headerRow: some View {
        CodeExecutionTimelineHeaderRow(
            title: headerTitle,
            isStreaming: isStreaming,
            hasActiveExecution: hasActiveExecution,
            compactStatus: compactStatus,
            isExpanded: expansionBinding
        )
    }

    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { isExpanded },
            set: { newValue in
                if !newValue {
                    isExpanded = false
                    return
                }
                // First expand: mount collapsed so the height probe warms,
                // then open on the next turns (matches MCP / web search).
                if hasEverExpanded {
                    isExpanded = true
                    return
                }
                hasEverExpanded = true
                Task { @MainActor in
                    await Task.yield()
                    await Task.yield()
                    withAnimation(JinMotion.disclosure(expanding: true)) {
                        isExpanded = true
                    }
                }
            }
        )
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        CodeExecutionTimelineExpandedContentView(activities: activities)
    }

    // MARK: - Computed

    private var hasActiveExecution: Bool {
        CodeExecutionTimelineSupport.hasActiveExecution(activities)
    }

    private var headerTitle: String {
        CodeExecutionTimelineSupport.headerTitle(activityCount: activities.count)
    }

    private var compactStatus: ToolTimelinePresentationSupport.CompactStatusStyle? {
        CodeExecutionTimelineSupport.compactStatus(for: activities)
            .map(ToolTimelinePresentationSupport.CompactStatusStyle.init)
    }

    private var animationSignature: String {
        CodeExecutionTimelineSupport.animationSignature(for: activities)
    }
}
