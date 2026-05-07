import SwiftUI

struct AgentToolTimelineCollapsedSummaryRow: View {
    let title: String
    let isStreaming: Bool
    let runningCount: Int
    let compactStatus: ToolTimelinePresentationSupport.CompactStatusStyle?
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, runningCount > 0 {
                    ToolTimelinePresentationSupport.RunningIndicator()
                }

                if let compactStatus {
                    ToolTimelinePresentationSupport.CompactStatusBadge(style: compactStatus)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(duration: 0.25, bounce: 0.15), value: isExpanded)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AgentToolTimelineExpandedPanelView: View {
    let activities: [CodexToolActivity]
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                AgentToolEntryView(
                    activity: activity,
                    entryIndex: index,
                    isStreaming: isStreaming
                )
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.small)
    }
}

struct AgentToolEntryView: View {
    let activity: CodexToolActivity
    let entryIndex: Int
    let isStreaming: Bool

    @State private var isExpanded = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entryHeaderButton
            expandedContentContainer
        }
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 6)
        .animation(.spring(duration: 0.25, bounce: 0.1), value: isExpanded)
        .onAppear {
            withAnimation(.spring(duration: 0.4, bounce: 0.08).delay(Double(entryIndex) * 0.06)) {
                hasAppeared = true
            }
        }
    }

    private var entryHeaderButton: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                isExpanded.toggle()
            }
        } label: {
            entryHeaderContent
        }
        .buttonStyle(.plain)
    }

    private var entryHeaderContent: some View {
        HStack(spacing: JinSpacing.small) {
            Image(systemName: toolIconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(displayName)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            collapsedArgumentSummary

            Spacer(minLength: 0)

            statusPill
            disclosureIndicator
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var collapsedArgumentSummary: some View {
        if !isExpanded, let summary = argumentSummary {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.spring(duration: 0.25, bounce: 0.15), value: isExpanded)
    }

    private var expandedContentContainer: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
                    .padding(.top, JinSpacing.xSmall)
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.bottom, JinSpacing.small)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var statusPill: some View {
        let status = executionStatus
        let style = ToolTimelinePresentationSupport.terminalStatusStyle(for: status)

        ToolTimelinePresentationSupport.StatusPill(
            status: status,
            label: statusLabel(for: status),
            textColor: style.text,
            accentColor: style.accent
        )
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if let argsText = formattedArgumentsJSON {
                ToolCallCodeBlockView(
                    title: "Arguments",
                    text: argsText,
                    showsCopyButton: true
                )
            }

            if let output = activity.output {
                ToolCallCodeBlockView(
                    title: executionStatus == .error ? "Error" : "Output",
                    text: output,
                    showsCopyButton: true
                )
            } else if executionStatus == .running {
                waitingForResultRow
            }

            if executionStatus != .running, let rawOutputPath = activity.rawOutputPath {
                ToolOutputFileActionRowView(rawOutputPath: rawOutputPath)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var waitingForResultRow: some View {
        HStack(spacing: JinSpacing.small) {
            ToolTimelinePresentationSupport.RunningIndicator()
            Text("Waiting for result…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, JinSpacing.xSmall)
    }

    private var executionStatus: ToolCallExecutionStatus {
        AgentToolTimelineSupport.executionStatus(for: activity)
    }

    private var displayName: String {
        AgentToolTimelineSupport.displayName(for: activity.toolName)
    }

    private var toolIconName: String {
        AgentToolTimelineSupport.toolIconName(for: activity.toolName)
    }

    private var argumentSummary: String? {
        AgentToolTimelineSupport.argumentSummary(for: activity.arguments)
    }

    private var formattedArgumentsJSON: String? {
        AgentToolTimelineSupport.formattedArgumentsJSON(for: activity.arguments)
    }

    private func statusLabel(for status: ToolCallExecutionStatus) -> String {
        AgentToolTimelineSupport.statusLabel(for: status)
    }
}
