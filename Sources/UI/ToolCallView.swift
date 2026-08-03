import SwiftUI

// MARK: - Tool Call View (multi-tool list rows + standalone card)

struct ToolCallView: View {
    enum Chrome: Equatable {
        case card
        case inline
    }

    let toolCall: ToolCall
    let toolResult: ToolResult?
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool
    let showsServerTag: Bool
    let chrome: Chrome
    var onExpansionChanged: () -> Void = {}

    @State private var isExpanded = false
    @State private var hasMountedExpandedContent = false
    @State private var isRunningPulse = false
    @State private var isHovering = false

    init(
        toolCall: ToolCall,
        toolResult: ToolResult?,
        showsConnectorAbove: Bool = false,
        showsConnectorBelow: Bool = false,
        showsServerTag: Bool = true,
        chrome: Chrome = .card,
        onExpansionChanged: @escaping () -> Void = {}
    ) {
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.showsConnectorAbove = showsConnectorAbove
        self.showsConnectorBelow = showsConnectorBelow
        self.showsServerTag = showsServerTag
        self.chrome = chrome
        self.onExpansionChanged = onExpansionChanged
    }

    var body: some View {
        Group {
            switch chrome {
            case .card:
                cardChrome
            case .inline:
                inlineChrome
            }
        }
        .onAppear {
            updatePulseAnimation(for: resolvedStatus)
            if !hasMountedExpandedContent {
                hasMountedExpandedContent = true
            }
        }
        .onChange(of: resolvedStatus) { _, newValue in
            updatePulseAnimation(for: newValue)
        }
        .onChange(of: isExpanded) { _, _ in
            onExpansionChanged()
        }
    }

    // MARK: - Chrome

    private var cardChrome: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            ToolTimelinePresentationSupport.TerminalTimelineRail(
                status: resolvedStatus,
                style: statusStyle(for: resolvedStatus),
                showsConnectorAbove: showsConnectorAbove,
                showsConnectorBelow: showsConnectorBelow,
                isRunningPulse: isRunningPulse
            )

            bodyColumn
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, JinSpacing.small)
                .jinSurface(.subtle, cornerRadius: JinRadius.small)
        }
    }

    private var inlineChrome: some View {
        bodyColumn
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(isHovering ? JinSemanticColor.subtleSurface.opacity(0.65) : Color.clear)
            )
            .onHover { isHovering = $0 }
    }

    private var bodyColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            ToolCallHeaderRow(
                serverLabel: serverLabel,
                toolLabel: toolLabel,
                showsServerTag: showsServerTag,
                status: resolvedStatus,
                statusLabel: quietStatusLabel,
                durationText: durationText,
                statusStyle: statusStyle(for: resolvedStatus),
                isExpanded: isExpanded,
                quiet: chrome == .inline,
                onToggle: toggleExpanded
            )

            if let argumentSummary {
                ToolCallArgumentSummaryView(argumentSummary: argumentSummary)
                    .opacity(isExpanded ? 0.5 : 1)
                    .frame(height: isExpanded ? 0 : nil, alignment: .top)
                    .clipped()
                    .allowsHitTesting(!isExpanded)
                    .accessibilityHidden(isExpanded)
            }

            if hasMountedExpandedContent {
                JinCollapsibleContent(isExpanded: isExpanded) {
                    ToolCallExpandedContentView(
                        formattedArgumentsJSON: formattedArgumentsJSON,
                        toolResult: toolResult,
                        signature: toolCall.signature
                    )
                    .padding(.top, 2)
                }
            }
        }
    }

    /// Success: no "Done" word — checkmark + duration is enough (Claude/Cursor).
    private var quietStatusLabel: String {
        switch resolvedStatus {
        case .success: return ""
        case .error: return "Failed"
        case .running: return "Running"
        }
    }

    private func toggleExpanded() {
        let expanding = !isExpanded
        if expanding, !hasMountedExpandedContent {
            hasMountedExpandedContent = true
        }
        withAnimation(JinMotion.disclosure(expanding: expanding)) {
            isExpanded = expanding
        }
    }

    // MARK: - Computed

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

    private func updatePulseAnimation(for status: ToolCallExecutionStatus) {
        isRunningPulse = status == .running
    }

    private func statusStyle(for status: ToolCallExecutionStatus) -> ToolTimelinePresentationSupport.StatusVisualStyle {
        ToolTimelinePresentationSupport.terminalStatusStyle(for: status)
    }
}
