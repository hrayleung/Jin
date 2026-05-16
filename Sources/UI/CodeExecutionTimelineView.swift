import SwiftUI

/// Displays a timeline of code execution activities from provider-native code execution tools
/// (OpenAI Code Interpreter, Anthropic Code Execution, xAI Code Interpreter).
struct CodeExecutionTimelineView: View {
    let activities: [CodeExecutionActivity]
    let isStreaming: Bool

    @State private var isExpanded: Bool

    init(activities: [CodeExecutionActivity], isStreaming: Bool) {
        self.activities = activities
        self.isStreaming = isStreaming
        let mode = Self.resolveDisplayMode()
        _isExpanded = State(
            initialValue: CodeExecutionTimelineSupport.initialExpansion(
                isStreaming: isStreaming,
                displayMode: mode
            )
        )
    }

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedContent
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipped()
            }
            .clipped()
            .animation(.spring(duration: 0.25, bounce: 0), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: animationSignature)
            .onChange(of: isStreaming) { _, streaming in
                let mode = Self.resolveDisplayMode()
                if let shouldExpand = CodeExecutionTimelineSupport.shouldExpandAfterStreamingChange(
                    isStreaming: streaming,
                    displayMode: mode
                ) {
                    withAnimation(.spring(duration: 0.25, bounce: 0)) {
                        isExpanded = shouldExpand
                    }
                }
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
            isExpanded: $isExpanded
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
