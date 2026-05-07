import SwiftUI

// MARK: - Tool Call View

struct ToolCallView: View {
    let toolCall: ToolCall
    let toolResult: ToolResult?
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool
    let showsServerTag: Bool

    @State private var isExpanded = false
    @State private var isRunningPulse = false

    init(
        toolCall: ToolCall,
        toolResult: ToolResult?,
        showsConnectorAbove: Bool = false,
        showsConnectorBelow: Bool = false,
        showsServerTag: Bool = true
    ) {
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.showsConnectorAbove = showsConnectorAbove
        self.showsConnectorBelow = showsConnectorBelow
        self.showsServerTag = showsServerTag
    }

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            ToolTimelinePresentationSupport.TerminalTimelineRail(
                status: resolvedStatus,
                style: statusStyle(for: resolvedStatus),
                showsConnectorAbove: showsConnectorAbove,
                showsConnectorBelow: showsConnectorBelow,
                isRunningPulse: isRunningPulse
            )

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                ToolCallHeaderRow(
                    serverLabel: serverLabel,
                    toolLabel: toolLabel,
                    showsServerTag: showsServerTag,
                    status: resolvedStatus,
                    statusLabel: statusLabel(for: resolvedStatus),
                    durationText: durationText,
                    statusStyle: statusStyle(for: resolvedStatus),
                    isExpanded: $isExpanded
                )

                if !isExpanded, let argumentSummary {
                    ToolCallArgumentSummaryView(argumentSummary: argumentSummary)
                }

                VStack(spacing: 0) {
                    if isExpanded {
                        ToolCallExpandedContentView(
                            formattedArgumentsJSON: formattedArgumentsJSON,
                            toolResult: toolResult,
                            signature: toolCall.signature
                        )
                            .padding(.top, JinSpacing.xSmall)
                    }
                }
                .clipped()
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.vertical, JinSpacing.small)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
        .animation(.spring(duration: 0.25, bounce: 0), value: isExpanded)
        .animation(.spring(duration: 0.24, bounce: 0), value: resolvedStatus)
        .onAppear {
            updatePulseAnimation(for: resolvedStatus)
        }
        .onChange(of: resolvedStatus) { _, newValue in
            updatePulseAnimation(for: newValue)
        }
    }

    // MARK: - Computed Properties

    private var formattedArgumentsJSON: String? {
        ToolCallViewSupport.formattedArgumentsJSON(for: toolCall.arguments)
    }

    private var parsedName: ToolCallViewSupport.ParsedFunctionName {
        ToolCallViewSupport.parseFunctionName(toolCall.name)
    }

    private var serverLabel: String {
        ToolCallViewSupport.serverLabel(for: parsedName)
    }

    private var toolLabel: String {
        parsedName.toolName
    }

    private var durationText: String? {
        ToolCallViewSupport.durationText(for: toolResult?.durationSeconds)
    }

    private var resolvedStatus: ToolCallExecutionStatus {
        ToolCallViewSupport.executionStatus(for: toolResult)
    }

    private var argumentSummary: String? {
        ToolCallViewSupport.argumentSummary(for: toolCall.arguments)
    }

    // MARK: - Helpers

    private func updatePulseAnimation(for status: ToolCallExecutionStatus) {
        isRunningPulse = status == .running
    }

    private func statusLabel(for status: ToolCallExecutionStatus) -> String {
        ToolCallViewSupport.statusLabel(for: status)
    }

    private func statusStyle(for status: ToolCallExecutionStatus) -> ToolTimelinePresentationSupport.StatusVisualStyle {
        ToolTimelinePresentationSupport.terminalStatusStyle(for: status)
    }

}
