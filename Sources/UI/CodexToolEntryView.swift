import SwiftUI

struct CodexToolEntryView: View {
    let entry: CodexToolTimelineSupport.Entry
    let entryIndex: Int
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool
    let isStreaming: Bool

    @State private var isExpanded = false
    @State private var isRunningPulse = false
    @State private var hasAppeared = false
    @State private var completionBounce = false

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            timelineRail(status: entry.executionStatus)

            contentColumn
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 6)
        .animation(.spring(duration: 0.25, bounce: 0.1), value: isExpanded)
        .animation(.spring(duration: 0.3, bounce: 0.08), value: entry.executionStatus)
        .onAppear {
            handleAppear()
        }
        .onChange(of: entry.executionStatus) { oldValue, newValue in
            handleStatusChange(from: oldValue, to: newValue)
        }
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            headerRow

            collapsedArgumentSummary

            expandedContentContainer
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.small + 2)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
            toolIcon

            toolNameText

            Spacer(minLength: 0)

            statusPill

            expandButton
        }
    }

    private var toolIcon: some View {
        Image(systemName: toolIconName(entry.activity.toolName))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var toolNameText: some View {
        Text(entry.activity.toolName)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var expandButton: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .accessibilityLabel(isExpanded ? "Collapse tool details" : "Expand tool details")
        .accessibilityHint("Shows or hides details for this tool activity")
        .buttonStyle(JinIconButtonStyle())
    }

    @ViewBuilder
    private var collapsedArgumentSummary: some View {
        if !isExpanded, let summary = argumentSummary {
            Text("-> \(summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var expandedContentContainer: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
                    .padding(.top, JinSpacing.xSmall)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func timelineRail(status: ToolCallExecutionStatus) -> some View {
        VStack(spacing: 0) {
            connectorSegment(visible: showsConnectorAbove)

            statusNode(status: status)

            connectorSegment(visible: showsConnectorBelow)
        }
        .frame(width: 20)
        .padding(.top, JinSpacing.small)
    }

    @ViewBuilder
    private func connectorSegment(visible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(
                LinearGradient(
                    colors: [
                        JinSemanticColor.separator.opacity(0.35),
                        JinSemanticColor.separator.opacity(0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1.5, height: 14)
            .opacity(visible ? 1 : 0)
    }

    @ViewBuilder
    private func statusNode(status: ToolCallExecutionStatus) -> some View {
        let style = statusStyle(for: status)
        let nodeSize: CGFloat = 18

        ZStack {
            if status == .running {
                Circle()
                    .fill(style.glowColor)
                    .frame(width: nodeSize + 8, height: nodeSize + 8)
                    .blur(radius: 4)
                    .opacity(isRunningPulse ? 0.5 : 0.15)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isRunningPulse
                    )
            }

            if status == .running {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                style.accent.opacity(0),
                                style.accent.opacity(0.5),
                                style.accent.opacity(0)
                            ]),
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: nodeSize + 2, height: nodeSize + 2)
                    .rotationEffect(.degrees(isRunningPulse ? 360 : 0))
                    .animation(
                        .linear(duration: 1.8).repeatForever(autoreverses: false),
                        value: isRunningPulse
                    )
            }

            Circle()
                .fill(style.nodeBackground)
                .frame(width: nodeSize, height: nodeSize)
                .overlay(
                    Circle()
                        .stroke(style.nodeBorder, lineWidth: 0.75)
                )

            Group {
                switch status {
                case .running:
                    Circle()
                        .fill(style.accent)
                        .frame(width: 5.5, height: 5.5)
                        .scaleEffect(isRunningPulse ? 1.3 : 0.8)
                        .opacity(isRunningPulse ? 0.5 : 1)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: isRunningPulse
                        )
                case .success:
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(style.accent)
                case .error:
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(style.accent)
                }
            }
            .scaleEffect(completionBounce ? 1.25 : 1)
        }
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

            if let output = entry.activity.output {
                ToolCallCodeBlockView(
                    title: entry.executionStatus == .error ? "Error" : "Output",
                    text: output,
                    showsCopyButton: true
                )
            } else if entry.executionStatus == .running {
                HStack(spacing: JinSpacing.small) {
                    ToolTimelinePresentationSupport.RunningIndicator()
                    Text("Waiting for result...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var statusPill: some View {
        let status = entry.executionStatus
        let style = statusStyle(for: status)

        ToolTimelinePresentationSupport.StatusPill(
            status: status,
            label: statusLabel(for: status),
            textColor: style.text,
            accentColor: style.accent
        )
    }

    private var formattedArgumentsJSON: String? {
        CodexToolTimelineSupport.formattedArgumentsJSON(for: entry.activity.arguments)
    }

    private var argumentSummary: String? {
        CodexToolTimelineSupport.argumentSummary(for: entry.activity.arguments)
    }

    private func handleAppear() {
        updatePulseAnimation(for: entry.executionStatus)
        withAnimation(.spring(duration: 0.4, bounce: 0.08).delay(Double(entryIndex) * 0.06)) {
            hasAppeared = true
        }
    }

    private func handleStatusChange(
        from oldValue: ToolCallExecutionStatus,
        to newValue: ToolCallExecutionStatus
    ) {
        updatePulseAnimation(for: newValue)
        if oldValue == .running && (newValue == .success || newValue == .error) {
            triggerCompletionBounce()
        }
    }

    private func triggerCompletionBounce() {
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            completionBounce = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            completionBounce = false
        }
    }

    private func updatePulseAnimation(for status: ToolCallExecutionStatus) {
        isRunningPulse = status == .running
    }

    private func statusLabel(for status: ToolCallExecutionStatus) -> String {
        CodexToolTimelineSupport.statusLabel(for: status)
    }

    private func statusStyle(for status: ToolCallExecutionStatus) -> ToolTimelinePresentationSupport.StatusVisualStyle {
        ToolTimelinePresentationSupport.accentStatusStyle(for: status)
    }

    private func toolIconName(_ name: String) -> String {
        CodexToolTimelineSupport.toolIconName(for: name)
    }
}
