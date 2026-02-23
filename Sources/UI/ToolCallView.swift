import SwiftUI

// MARK: - Tool Call Status

enum ToolCallExecutionStatus: Equatable {
    case running
    case success
    case error
}

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
            timelineRail(status: resolvedStatus)

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: JinSpacing.small) {
                    if showsServerTag {
                        serverTag
                    }

                    Text(toolLabel)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(JinIconButtonStyle())
                }

                if !isExpanded, let argumentSummary {
                    Text("-> \(argumentSummary)")
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
        .animation(.spring(duration: 0.24, bounce: 0), value: resolvedStatus)
        .onAppear {
            updatePulseAnimation(for: resolvedStatus)
        }
        .onChange(of: resolvedStatus) { _, newValue in
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
        ZStack {
            Circle()
                .fill(statusColor(for: status).opacity(status == .running ? 0.18 : 0.14))
                .frame(width: 16, height: 16)

            switch status {
            case .running:
                Circle()
                    .fill(statusColor(for: status))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isRunningPulse ? 1.4 : 0.85)
                    .opacity(isRunningPulse ? 0.35 : 1)
                    .animation(
                        .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
                        value: isRunningPulse
                    )
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor(for: status))
            case .error:
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor(for: status))
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            ToolCallCodeBlockView(
                title: "Arguments",
                text: formattedArgumentsJSON ?? "{}"
            )

            if let toolResult {
                ToolCallCodeBlockView(
                    title: toolResult.isError ? "Error" : "Output",
                    text: toolResult.content
                )
            } else {
                Text("Waiting for tool result...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let signature = toolCall.signature, !signature.isEmpty {
                ToolCallCodeBlockView(title: "Signature", text: signature)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        let status = resolvedStatus
        let foreground = statusColor(for: status)

        HStack(spacing: 6) {
            statusPillGlyph(for: status)

            Text(statusLabel(for: status))

            if let durationText {
                Text(durationText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .jinTagStyle(foreground: foreground)
    }

    @ViewBuilder
    private func statusPillGlyph(for status: ToolCallExecutionStatus) -> some View {
        switch status {
        case .running:
            Circle()
                .fill(statusColor(for: status))
                .frame(width: 5, height: 5)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor(for: status))
        }
    }

    // MARK: - Computed Properties

    private var formattedArgumentsJSON: String? {
        let raw = toolCall.arguments.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw),
              let argsJSON = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let argsString = String(data: argsJSON, encoding: .utf8) else {
            return nil
        }
        return argsString
    }

    private var parsedName: (serverID: String, toolName: String) {
        splitFunctionName(toolCall.name)
    }

    private var serverLabel: String {
        if parsedName.serverID.isEmpty {
            return "mcp"
        }
        return parsedName.serverID
    }

    private var serverTag: some View {
        Text(serverLabel)
            .jinTagStyle()
    }

    private var toolLabel: String {
        parsedName.toolName
    }

    private var durationText: String? {
        guard let seconds = toolResult?.durationSeconds, seconds > 0 else { return nil }
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return "\(Int(seconds.rounded()))s"
    }

    private var resolvedStatus: ToolCallExecutionStatus {
        guard let toolResult else { return .running }
        return toolResult.isError ? .error : .success
    }

    private var argumentSummary: String? {
        let raw = toolCall.arguments.mapValues { $0.value }
        guard !raw.isEmpty else { return nil }

        let preferredKeys = ["query", "q", "url", "input", "text"]
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
        case .success: return "Success"
        case .error: return "Error"
        }
    }

    private func statusColor(for status: ToolCallExecutionStatus) -> Color {
        switch status {
        case .running: return .secondary
        case .success: return .secondary
        case .error: return .orange
        }
    }

    private func splitFunctionName(_ name: String) -> (serverID: String, toolName: String) {
        guard let range = name.range(of: "__") else { return ("", name) }
        let serverID = String(name[..<range.lowerBound])
        let toolName = String(name[range.upperBound...])
        return (serverID, toolName.isEmpty ? name : toolName)
    }

    private func oneLine(_ string: String, maxLength: Int) -> String {
        let condensed = string
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 3)) + "..."
    }
}

// MARK: - Tool Call Code Block

struct ToolCallCodeBlockView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small - 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(JinSpacing.medium - 2)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }
}
