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

    private static func resolveDisplayMode() -> CodexToolDisplayMode {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKeys.codexToolDisplayMode) ?? ""
        return CodexToolDisplayMode(rawValue: raw) ?? .expanded
    }

    // MARK: - Collapsed Summary Row

    private var collapsedSummaryRow: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.05)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                ZStack {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 18, height: 18)

                Text(collapsedTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isStreaming, runningCount > 0 {
                    CodexActivityIndicator()
                }

                if let compactStatusStyle {
                    CodexCompactStatusBadge(style: compactStatusStyle)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(duration: 0.25, bounce: 0.15), value: isExpanded)
            }
            .padding(.horizontal, JinSpacing.small)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small + 2) {
            HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                Text(entries.count == 1 ? "Codex Tool" : "Codex Tools")
                    .font(.headline)

                if let statusSummaryText {
                    Text(statusSummaryText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    CodexToolEntryView(
                        entry: entry,
                        entryIndex: index,
                        showsConnectorAbove: index > 0,
                        showsConnectorBelow: index < entries.count - 1,
                        isStreaming: isStreaming
                    )
                }
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall + 2)
        .padding(.bottom, JinSpacing.small)
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
                    icon: "xmark.circle.fill",
                    color: Color(nsColor: .systemOrange)
                )
            }
            return CodexCompactStatusStyle(
                text: summaryCountText(errorCount, singular: "failed", plural: "failed"),
                icon: "xmark.circle.fill",
                color: Color(nsColor: .systemOrange)
            )
        }

        if successCount > 0 {
            return CodexCompactStatusStyle(
                text: successCount == 1 ? "Succeeded" : "All succeeded",
                icon: "checkmark.circle.fill",
                color: Color(nsColor: .systemGreen)
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

        return parts.isEmpty ? nil : "(" + parts.joined(separator: " / ") + ")"
    }

    private func summaryCountText(_ count: Int, singular: String, plural: String) -> String {
        if count <= 1 {
            return singular
        }
        return "\(count) \(plural)"
    }

    private var entryAnimationSignature: String {
        entries
            .map { "\($0.id):\($0.executionStatus)" }
            .joined(separator: "|")
    }
}

// MARK: - Compact Status Badge

private struct CodexCompactStatusBadge: View {
    let style: CodexCompactStatusStyle

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

// MARK: - Activity Indicator (3-dot wave)

private struct CodexActivityIndicator: View {
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

// MARK: - CodexToolEntryView

private struct CodexToolEntryView: View {
    let entry: CodexToolTimelineEntry
    let entryIndex: Int
    let showsConnectorAbove: Bool
    let showsConnectorBelow: Bool
    let isStreaming: Bool

    @State private var isExpanded = false
    @State private var isRunningPulse = false
    @State private var hasAppeared = false
    @State private var completionBounce = false

    private struct StatusVisualStyle {
        let accent: Color
        let text: Color
        let nodeBackground: Color
        let nodeBorder: Color
        let glowColor: Color
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
            .padding(.vertical, JinSpacing.small + 2)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 6)
        .animation(.spring(duration: 0.25, bounce: 0.1), value: isExpanded)
        .animation(.spring(duration: 0.3, bounce: 0.08), value: entry.executionStatus)
        .onAppear {
            updatePulseAnimation(for: entry.executionStatus)
            withAnimation(.spring(duration: 0.4, bounce: 0.08).delay(Double(entryIndex) * 0.06)) {
                hasAppeared = true
            }
        }
        .onChange(of: entry.executionStatus) { oldValue, newValue in
            updatePulseAnimation(for: newValue)
            if oldValue == .running && (newValue == .success || newValue == .error) {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                    completionBounce = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    completionBounce = false
                }
            }
        }
    }

    // MARK: - Timeline Rail

    @ViewBuilder
    private func timelineRail(status: ToolCallExecutionStatus) -> some View {
        let style = statusStyle(for: status)

        VStack(spacing: 0) {
            connectorSegment(visible: showsConnectorAbove, style: style)

            statusNode(status: status)

            connectorSegment(visible: showsConnectorBelow, style: style)
        }
        .frame(width: 20)
        .padding(.top, JinSpacing.small)
    }

    @ViewBuilder
    private func connectorSegment(visible: Bool, style: StatusVisualStyle) -> some View {
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
            // Glow halo for running state
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

            // Spinning ring for running state
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

            // Base circle
            Circle()
                .fill(style.nodeBackground)
                .frame(width: nodeSize, height: nodeSize)
                .overlay(
                    Circle()
                        .stroke(style.nodeBorder, lineWidth: 0.75)
                )

            // Status icon
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
                HStack(spacing: JinSpacing.small) {
                    CodexActivityIndicator()
                    Text("Waiting for result...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, JinSpacing.xSmall)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        let status = entry.executionStatus
        let style = statusStyle(for: status)

        HStack(spacing: 5) {
            statusPillGlyph(for: status)
            Text(statusLabel(for: status))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(style.text)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(style.accent.opacity(0.1))
        )
        .lineLimit(1)
    }

    @ViewBuilder
    private func statusPillGlyph(for status: ToolCallExecutionStatus) -> some View {
        let style = statusStyle(for: status)

        switch status {
        case .running:
            Circle()
                .fill(style.accent)
                .frame(width: 4, height: 4)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(style.accent)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 9.5, weight: .semibold))
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
                accent: Color.accentColor.opacity(0.7),
                text: .secondary,
                nodeBackground: Color.accentColor.opacity(0.08),
                nodeBorder: Color.accentColor.opacity(0.2),
                glowColor: Color.accentColor.opacity(0.25)
            )
        case .success:
            return StatusVisualStyle(
                accent: Color(nsColor: .systemGreen).opacity(0.88),
                text: Color(nsColor: .systemGreen).opacity(0.88),
                nodeBackground: Color(nsColor: .systemGreen).opacity(0.11),
                nodeBorder: Color(nsColor: .systemGreen).opacity(0.26),
                glowColor: Color(nsColor: .systemGreen).opacity(0.15)
            )
        case .error:
            return StatusVisualStyle(
                accent: Color(nsColor: .systemOrange).opacity(0.95),
                text: Color(nsColor: .systemOrange).opacity(0.95),
                nodeBackground: Color(nsColor: .systemOrange).opacity(0.14),
                nodeBorder: Color(nsColor: .systemOrange).opacity(0.36),
                glowColor: Color(nsColor: .systemOrange).opacity(0.15)
            )
        }
    }

    private func toolIconName(_ name: String) -> String {
        let lower = name.lowercased()
        let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
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
        if lower.contains("write") || lower.contains("edit") || lower.contains("patch")
            || lower.contains("create_file") || lower.contains("apply")
            || lower.hasPrefix("file change") || lower.contains("file_change")
            || lower.contains(": ")
        {
            return "pencil.line"
        }
        if lower.contains("read") || lower.contains("cat") || lower.contains("view")
            || lower.contains("get_file") || lower.contains("image view") {
            return "doc.text"
        }
        if lower.contains("search") || lower.contains("grep") || lower.contains("find")
            || lower.contains("ripgrep") || tokens.contains(where: { $0 == "rg" }) {
            return "magnifyingglass"
        }
        if lower.hasPrefix("ls") || lower.hasPrefix("dir")
            || lower.contains("list") || lower.contains("tree") {
            return "folder"
        }
        if lower.contains("mcp") || lower.contains("/") {
            return "puzzlepiece"
        }
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
