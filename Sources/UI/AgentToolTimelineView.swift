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
        if isStreaming {
            _isExpanded = State(initialValue: mode.startsExpandedDuringStreaming)
        } else {
            _isExpanded = State(initialValue: mode.startsExpandedOnComplete)
        }
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
                if streaming {
                    let mode = Self.resolveDisplayMode()
                    if mode.startsExpandedDuringStreaming {
                        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                            isExpanded = true
                        }
                    }
                } else {
                    let mode = Self.resolveDisplayMode()
                    if mode == .collapseOnComplete {
                        withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                            isExpanded = false
                        }
                    }
                }
            }
        }
    }

    private static func resolveDisplayMode() -> AgentToolDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.agentToolDisplayMode) ?? ""
        return AgentToolDisplayMode(rawValue: raw) ?? .expanded
    }

    // MARK: - Collapsed Summary Row

    private var collapsedSummaryRow: some View {
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

                Text(collapsedTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, runningCount > 0 {
                    AgentRunningIndicator()
                }

                if let compactStatus {
                    AgentCompactBadge(style: compactStatus)
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

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
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

    // MARK: - Derived Content

    private var runningCount: Int {
        activities.filter {
            if case .running = $0.status { return true }
            if case .unknown = $0.status { return true }
            return false
        }.count
    }
    private var successCount: Int { activities.filter { $0.status == .completed }.count }
    private var errorCount: Int { activities.filter { $0.status == .failed }.count }

    private var collapsedTitle: String {
        if activities.count == 1 {
            return "Agent · \(agentToolDisplayName(activities[0].toolName))"
        }
        if runningCount > 0 {
            return "Agent · \(runningCount) running"
        }
        return "Agent · \(activities.count) tools"
    }

    private var compactStatus: AgentStatusStyle? {
        if runningCount > 0 { return nil }

        if errorCount > 0 {
            let label = successCount > 0
                ? "\(successCount) ok / \(errorCount) failed"
                : (errorCount == 1 ? "Failed" : "\(errorCount) failed")
            return AgentStatusStyle(
                text: label,
                icon: "xmark.circle.fill",
                color: Color(nsColor: .systemOrange)
            )
        }

        if successCount > 0 {
            return AgentStatusStyle(
                text: successCount == 1 ? "Succeeded" : "All succeeded",
                icon: "checkmark.circle.fill",
                color: Color(nsColor: .systemGreen)
            )
        }

        return nil
    }

    private var entryAnimationSignature: String {
        activities.map { "\($0.id):\($0.status)" }.joined(separator: "|")
    }

    private func agentToolDisplayName(_ name: String) -> String {
        name.replacingOccurrences(of: "agent__", with: "")
    }
}

// MARK: - Compact Badge

private struct AgentStatusStyle {
    let text: String
    let icon: String
    let color: Color
}

private struct AgentCompactBadge: View {
    let style: AgentStatusStyle

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(style.text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(style.color.opacity(0.9))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(style.color.opacity(0.1))
        )
        .lineLimit(1)
    }
}

// MARK: - Running Indicator

private struct AgentRunningIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: isAnimating ? -2.5 : 2.5)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .frame(height: 10)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Entry View

private struct AgentToolEntryView: View {
    let activity: CodexToolActivity
    let entryIndex: Int
    let isStreaming: Bool

    @State private var isExpanded = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: JinSpacing.small) {
                    Image(systemName: toolIconName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(displayName)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !isExpanded, let summary = argumentSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    statusPill

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(duration: 0.25, bounce: 0.15), value: isExpanded)
                }
                .padding(.horizontal, JinSpacing.medium)
                .padding(.vertical, JinSpacing.small + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        let status = executionStatus

        HStack(spacing: 5) {
            statusPillGlyph(for: status)
            Text(statusLabel(for: status))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(statusColor(for: status))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(statusColor(for: status).opacity(0.1))
        )
        .lineLimit(1)
    }

    @ViewBuilder
    private func statusPillGlyph(for status: ToolCallExecutionStatus) -> some View {
        switch status {
        case .running:
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 4, height: 4)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        }
    }

    // MARK: - Expanded Content

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
                HStack(spacing: JinSpacing.small) {
                    AgentRunningIndicator()
                    Text("Waiting for result…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, JinSpacing.xSmall)
            }

            if executionStatus != .running, let rawOutputPath = activity.rawOutputPath {
                ToolOutputFileActionRowView(rawOutputPath: rawOutputPath)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Computed

    private var executionStatus: ToolCallExecutionStatus {
        switch activity.status {
        case .running, .unknown(_): return .running
        case .completed: return .success
        case .failed: return .error
        }
    }

    private var displayName: String {
        activity.toolName.replacingOccurrences(of: "agent__", with: "")
    }

    private var toolIconName: String {
        let lower = activity.toolName.lowercased()
        if lower.contains("shell") || lower.contains("execute") { return "terminal" }
        if lower.contains("file_read") || lower.contains("read") { return "doc.text" }
        if lower.contains("file_write") || lower.contains("write") { return "square.and.pencil" }
        if lower.contains("file_edit") || lower.contains("edit") { return "pencil.line" }
        if lower.contains("glob") { return "doc.text.magnifyingglass" }
        if lower.contains("grep") { return "magnifyingglass" }
        return "gearshape"
    }

    private var argumentSummary: String? {
        let raw = activity.arguments.mapValues { $0.value }
        guard !raw.isEmpty else { return nil }
        let preferredKeys = ["command", "cmd", "path", "file", "filePath", "file_path", "pattern", "query"]
        for key in preferredKeys {
            if let value = raw[key] as? String {
                return oneLine(value, maxLength: 120)
            }
        }
        return nil
    }

    private var formattedArgumentsJSON: String? {
        let raw = activity.arguments.mapValues { $0.value }
        guard !raw.isEmpty,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func statusLabel(for status: ToolCallExecutionStatus) -> String {
        switch status {
        case .running: return "Running"
        case .success: return "Done"
        case .error: return "Failed"
        }
    }

    private func statusColor(for status: ToolCallExecutionStatus) -> Color {
        switch status {
        case .running: return .secondary
        case .success: return Color(nsColor: .systemGreen).opacity(0.88)
        case .error: return Color(nsColor: .systemOrange).opacity(0.95)
        }
    }

    private func oneLine(_ string: String, maxLength: Int) -> String {
        let condensed = string
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 3)) + "..."
    }
}
