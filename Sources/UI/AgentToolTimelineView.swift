import SwiftUI

// MARK: - AgentToolTimelineView

struct AgentToolTimelineView: View {
    let activities: [CodexToolActivity]
    let isStreaming: Bool

    @State private var isExpanded = true

    var body: some View {
        if !activities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                            AgentToolEntryRow(
                                activity: activity,
                                entryIndex: index,
                                isStreaming: isStreaming
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(headerAccentColor)

                Text("Agent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if activities.count > 1 {
                    Text("\(activities.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }

                Spacer(minLength: 0)

                if isStreaming, runningCount > 0 {
                    AgentPulsingDot()
                }

                headerStatusLabel

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.quaternary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerAccentColor: Color {
        if runningCount > 0 { return .accentColor }
        if errorCount > 0 { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemGreen)
    }

    @ViewBuilder
    private var headerStatusLabel: some View {
        if runningCount > 0 {
            Text(runningCount == activities.count ? "Running" : "\(runningCount) running")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        } else if errorCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                Text(errorCount == activities.count ? "Failed" : "\(errorCount) failed")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(Color(nsColor: .systemOrange))
        } else if successCount == activities.count {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text("Done")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(Color(nsColor: .systemGreen).opacity(0.85))
        }
    }

    // MARK: - Counts

    private var runningCount: Int { activities.filter { $0.status == .running }.count }
    private var successCount: Int { activities.filter { $0.status == .completed }.count }
    private var errorCount: Int { activities.filter { $0.status == .failed }.count }
}

// MARK: - Entry Row

private struct AgentToolEntryRow: View {
    let activity: CodexToolActivity
    let entryIndex: Int
    let isStreaming: Bool

    @State private var isExpanded = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: toolIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)

                    Text(displayName)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)

                    if !isExpanded, let summary = argumentSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)

                    statusIndicator
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedDetail
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isExpanded ? Color.primary.opacity(0.03) : Color.clear)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 4)
        .animation(.easeOut(duration: 0.2), value: isExpanded)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25).delay(Double(entryIndex) * 0.04)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch activity.status {
        case .running:
            AgentPulsingDot()
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemGreen).opacity(0.75))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemOrange).opacity(0.85))
        case .unknown:
            AgentPulsingDot()
        }
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let argsText = formattedArguments {
                AgentDetailBlock(label: "Input", text: argsText)
            }

            if let output = activity.output {
                AgentDetailBlock(
                    label: activity.status == .failed ? "Error" : "Output",
                    text: output,
                    isError: activity.status == .failed
                )
            } else if activity.status == .running {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Running...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Computed

    private var displayName: String {
        activity.toolName.replacingOccurrences(of: "agent__", with: "")
    }

    private var toolIcon: String {
        let name = activity.toolName.lowercased()
        if name.contains("shell") || name.contains("execute") { return "terminal" }
        if name.contains("file_read") || name.contains("read") { return "doc.text" }
        if name.contains("file_write") || name.contains("write") { return "square.and.pencil" }
        if name.contains("file_edit") || name.contains("edit") { return "pencil.line" }
        if name.contains("glob") { return "doc.text.magnifyingglass" }
        if name.contains("grep") { return "magnifyingglass" }
        return "gearshape"
    }

    private var argumentSummary: String? {
        let raw = activity.arguments.mapValues { $0.value }
        guard !raw.isEmpty else { return nil }
        let keys = ["command", "cmd", "path", "file", "filePath", "file_path", "pattern", "query"]
        for key in keys {
            if let value = raw[key] as? String {
                return oneLine(value, max: 80)
            }
        }
        return nil
    }

    private var formattedArguments: String? {
        let raw = activity.arguments.mapValues { $0.value }
        guard !raw.isEmpty,
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func oneLine(_ string: String, max: Int) -> String {
        let condensed = string.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return condensed.count > max ? String(condensed.prefix(max - 1)) + "…" : condensed
    }
}

// MARK: - Detail Block

private struct AgentDetailBlock: View {
    let label: String
    let text: String
    var isError: Bool = false

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isError ? AnyShapeStyle(Color(nsColor: .systemOrange).opacity(0.8)) : AnyShapeStyle(.tertiary))
                    .textCase(.uppercase)

                Spacer()

                if isHovered {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Pulsing Dot

private struct AgentPulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
            .opacity(isPulsing ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
