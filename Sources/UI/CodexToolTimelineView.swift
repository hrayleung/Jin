import SwiftUI

// MARK: - Entry Model

private struct CodexToolTimelineEntry: Identifiable {
    let activity: CodexToolActivity

    var id: String { activity.id }

    var executionStatus: ToolCallExecutionStatus {
        switch activity.status {
        case .running:
            return .running
        case .completed:
            return .success
        case .failed:
            return .error
        case .unknown:
            return .running
        }
    }
}

private struct CodexCompactStatusStyle {
    let text: String
    let icon: String
    let color: Color
}

// MARK: - CodexToolTimelineView

struct CodexToolTimelineView: View {
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
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                collapsedSummaryRow

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipped()
            }
            .padding(JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
            .clipped()
            .animation(.spring(duration: 0.25, bounce: 0), value: isExpanded)
            .animation(.easeInOut(duration: 0.2), value: entryAnimationSignature)
            .onChange(of: isStreaming) { _, streaming in
                if streaming {
                    let mode = Self.resolveDisplayMode()
                    if mode.startsExpandedDuringStreaming {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded = true
                        }
                    }
                } else {
                    let mode = Self.resolveDisplayMode()
                    if mode == .collapseOnComplete {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded = false
                        }
                    }
                }
            }
        }
    }

    private static func resolveDisplayMode() -> CodexToolDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.codexToolDisplayMode) ?? ""
        return CodexToolDisplayMode(rawValue: raw) ?? .expanded
    }

    // MARK: - Subviews

    private var collapsedSummaryRow: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)

                Text(collapsedTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, runningCount > 0 {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                if let compactStatusStyle {
                    HStack(spacing: 4) {
                        Image(systemName: compactStatusStyle.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(compactStatusStyle.text)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(compactStatusStyle.color)
                    .lineLimit(1)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small - 2) {
                Text(entries.count == 1 ? "Codex Tool" : "Codex Tools")
                    .font(.headline)

                if let statusSummaryText {
                    Text("(\(statusSummaryText))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    CodexToolEntryView(
                        entry: entry,
                        showsConnectorAbove: index > 0,
                        showsConnectorBelow: index < entries.count - 1
                    )
                }
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.xSmall)
    }

    // MARK: - Derived Content

    private var entries: [CodexToolTimelineEntry] {
        activities.map { CodexToolTimelineEntry(activity: $0) }
    }

    private var runningCount: Int {
        entries.filter { $0.executionStatus == .running }.count
    }

    private var successCount: Int {
        entries.filter { $0.executionStatus == .success }.count
    }

    private var errorCount: Int {
        entries.filter { $0.executionStatus == .error }.count
    }

    private var collapsedTitle: String {
        let toolLabel = entries.count == 1
            ? oneLine(entries[0].activity.toolName, maxLength: 60)
            : "\(entries.count) tools"

        if runningCount > 0, entries.count > 1 {
            return "Codex: \(runningCount) running"
        }
        return "Codex: \(toolLabel)"
    }

    private func oneLine(_ string: String, maxLength: Int) -> String {
        let condensed = string
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 3)) + "..."
    }

    private var compactStatusStyle: CodexCompactStatusStyle? {
        if runningCount > 0 {
            return nil
        }

        if errorCount > 0 {
            if successCount > 0 {
                return CodexCompactStatusStyle(
                    text: "\(summaryCountText(successCount, singular: "ok", plural: "ok")) / \(summaryCountText(errorCount, singular: "failed", plural: "failed"))",
                    icon: "xmark.circle",
                    color: Color(nsColor: .systemOrange).opacity(0.95)
                )
            }
            return CodexCompactStatusStyle(
                text: summaryCountText(errorCount, singular: "failed", plural: "failed"),
                icon: "xmark.circle",
                color: Color(nsColor: .systemOrange).opacity(0.95)
            )
        }

        if successCount > 0 {
            return CodexCompactStatusStyle(
                text: successCount == 1 ? "Succeeded" : "All succeeded",
                icon: "checkmark.circle",
                color: Color(nsColor: .systemGreen).opacity(0.88)
            )
        }

        return nil
    }

    private var statusSummaryText: String? {
        var parts: [String] = []

        if successCount > 0 {
            parts.append(summaryCountText(successCount, singular: "success", plural: "successes"))
        }
        if errorCount > 0 {
            parts.append(summaryCountText(errorCount, singular: "failed", plural: "failed"))
        }
        if runningCount > 0 {
            parts.append(summaryCountText(runningCount, singular: "running", plural: "running"))
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private func summaryCountText(_ count: Int, singular: String, plural: String) -> String {
        if count <= 1 {
            return singular
        }
        return "\(count) \(plural)"
    }

    private var entryAnimationSignature: String {
        entries
            .map { entry in
                "\(entry.id):\(entry.executionStatus)"
            }
            .joined(separator: "|")
    }
}

// MARK: - CodexToolEntryView

private struct CodexToolEntryView: View {
    let entry: CodexToolTimelineEntry
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool

    @State private var isExpanded = false
    @State private var isRunningPulse = false

    private struct StatusVisualStyle {
        let accent: Color
        let text: Color
        let nodeBackground: Color
        let nodeBorder: Color
    }

    var body: some View {
        HStack(alignment: .top, spacing: JinSpacing.small) {
            timelineRail(status: entry.executionStatus)

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                    Image(systemName: toolIconName(entry.activity.toolName))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(entry.activity.toolName)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    statusPill

                    Button {
                        withAnimation(.spring(duration: 0.25, bounce: 0)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(isExpanded ? "Collapse tool details" : "Expand tool details")
                    .accessibilityHint("Shows or hides details for this tool activity")
                    .buttonStyle(JinIconButtonStyle())
                }

                if !isExpanded, let summary = argumentSummary {
                    Text("-> \(summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                VStack(spacing: 0) {
                    if isExpanded {
                        expandedContent
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
        .animation(.spring(duration: 0.24, bounce: 0), value: entry.executionStatus)
        .onAppear {
            updatePulseAnimation(for: entry.executionStatus)
        }
        .onChange(of: entry.executionStatus) { _, newValue in
            updatePulseAnimation(for: newValue)
        }
    }

    // MARK: - Timeline Rail

    @ViewBuilder
    private func timelineRail(status: ToolCallExecutionStatus) -> some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.7))
                .frame(width: JinStrokeWidth.regular, height: 12)
                .opacity(showsConnectorAbove ? 1 : 0)

            statusNode(status: status)

            Rectangle()
                .fill(JinSemanticColor.separator.opacity(0.7))
                .frame(width: JinStrokeWidth.regular, height: 12)
                .opacity(showsConnectorBelow ? 1 : 0)
        }
        .frame(width: 16)
        .padding(.top, JinSpacing.xSmall)
    }

    @ViewBuilder
    private func statusNode(status: ToolCallExecutionStatus) -> some View {
        let style = statusStyle(for: status)

        ZStack {
            Circle()
                .fill(style.nodeBackground)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(style.nodeBorder, lineWidth: 0.75)
                )

            switch status {
            case .running:
                Circle()
                    .fill(style.accent)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isRunningPulse ? 1.4 : 0.85)
                    .opacity(isRunningPulse ? 0.35 : 1)
                    .animation(
                        .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: isRunningPulse
                    )
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
        }
    }

    // MARK: - Subviews

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
                Text("Waiting for result...")
                    .jinInfoCallout()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        let status = entry.executionStatus
        let style = statusStyle(for: status)

        HStack(spacing: 6) {
            statusPillGlyph(for: status)
            Text(statusLabel(for: status))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(style.text)
        .lineLimit(1)
    }

    @ViewBuilder
    private func statusPillGlyph(for status: ToolCallExecutionStatus) -> some View {
        let style = statusStyle(for: status)

        switch status {
        case .running:
            Circle()
                .fill(style.accent)
                .frame(width: 4.5, height: 4.5)
        case .success:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.accent)
        case .error:
            Image(systemName: "xmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.accent)
        }
    }

    // MARK: - Computed Properties

    private var formattedArgumentsJSON: String? {
        let raw = entry.activity.arguments.mapValues { $0.value }
        guard !raw.isEmpty else { return nil }
        guard JSONSerialization.isValidJSONObject(raw),
              let argsJSON = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let argsString = String(data: argsJSON, encoding: .utf8) else {
            return nil
        }
        return argsString
    }

    private var argumentSummary: String? {
        let raw = entry.activity.arguments.mapValues { $0.value }
        guard !raw.isEmpty else { return nil }

        let preferredKeys = ["command", "cmd", "path", "file", "filePath", "file_path", "query", "input", "text", "content"]
        for key in preferredKeys {
            if let value = raw[key] as? String {
                return oneLine(value, maxLength: 200)
            }
        }

        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return oneLine(json, maxLength: 200)
    }

    // MARK: - Helpers

    private func updatePulseAnimation(for status: ToolCallExecutionStatus) {
        isRunningPulse = status == .running
    }

    private func statusLabel(for status: ToolCallExecutionStatus) -> String {
        switch status {
        case .running: return "Running"
        case .success: return "Done"
        case .error: return "Failed"
        }
    }

    private func statusStyle(for status: ToolCallExecutionStatus) -> StatusVisualStyle {
        switch status {
        case .running:
            return StatusVisualStyle(
                accent: .secondary,
                text: .secondary,
                nodeBackground: Color.primary.opacity(0.08),
                nodeBorder: JinSemanticColor.separator.opacity(0.72)
            )
        case .success:
            return StatusVisualStyle(
                accent: Color(nsColor: .systemGreen).opacity(0.88),
                text: Color(nsColor: .systemGreen).opacity(0.88),
                nodeBackground: Color(nsColor: .systemGreen).opacity(0.11),
                nodeBorder: Color(nsColor: .systemGreen).opacity(0.26)
            )
        case .error:
            return StatusVisualStyle(
                accent: Color(nsColor: .systemOrange).opacity(0.95),
                text: Color(nsColor: .systemOrange).opacity(0.95),
                nodeBackground: Color(nsColor: .systemOrange).opacity(0.14),
                nodeBorder: Color(nsColor: .systemOrange).opacity(0.36)
            )
        }
    }

    private func toolIconName(_ name: String) -> String {
        let lower = name.lowercased()
        let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        // Shell / command execution
        if lower.contains("shell") || lower.contains("command") || lower.contains("exec")
            || lower.contains("bash") || lower.contains("terminal")
            || lower.hasPrefix("sh") || lower.hasPrefix("zsh")
            || lower.hasPrefix("python") || lower.hasPrefix("node")
            || lower.hasPrefix("npm") || lower.hasPrefix("cargo")
            || lower.hasPrefix("swift") || lower.hasPrefix("make")
            || lower.hasPrefix("git") || lower.hasPrefix("cd ")
            || lower.hasPrefix("echo") || lower.hasPrefix("curl") {
            return "terminal"
        }
        // File write / edit / patch
        if lower.contains("write") || lower.contains("edit") || lower.contains("patch")
            || lower.contains("create_file") || lower.contains("apply")
            || lower.hasPrefix("file change") || lower.contains("file_change")
            || lower.contains(": ") // e.g., "edit: main.swift"
        {
            return "pencil.line"
        }
        // File read
        if lower.contains("read") || lower.contains("cat") || lower.contains("view")
            || lower.contains("get_file") || lower.contains("image view") {
            return "doc.text"
        }
        // Search / grep
        if lower.contains("search") || lower.contains("grep") || lower.contains("find")
            || lower.contains("ripgrep") || tokens.contains(where: { $0 == "rg" }) {
            return "magnifyingglass"
        }
        // List / directory
        if lower.hasPrefix("ls") || lower.hasPrefix("dir")
            || lower.contains("list") || lower.contains("tree") {
            return "folder"
        }
        // MCP tool
        if lower.contains("mcp") || lower.contains("/") {
            return "puzzlepiece"
        }
        // Collaboration
        if lower.contains("collab") || lower.contains("spawn") || lower.contains("agent") {
            return "person.2"
        }
        return "gearshape"
    }

    private func oneLine(_ string: String, maxLength: Int) -> String {
        let condensed = string
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 3)) + "..."
    }
}
