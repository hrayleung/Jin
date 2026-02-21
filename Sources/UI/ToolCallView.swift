import SwiftUI

// MARK: - Tool Call View

struct ToolCallView: View {
    let toolCall: ToolCall
    let toolResult: ToolResult?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "hammer")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text(displayTitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                statusPill

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
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

            if isExpanded {
                expandedContent
            }
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.medium - 2)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium - 2) {
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
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Status Pill

    @ViewBuilder
    private var statusPill: some View {
        let status = resolvedStatus
        let foreground: Color = statusColor(for: status)

        HStack(spacing: 6) {
            switch status {
            case .running:
                ProgressView()
                    .scaleEffect(0.6)
                Text("Running")
            case .success:
                Image(systemName: "checkmark")
                Text("Success")
            case .error:
                Image(systemName: "xmark")
                Text("Error")
            }

            if let durationText {
                Text(durationText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .jinTagStyle(foreground: foreground)
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

    private var displayTitle: String {
        let (serverID, toolName) = splitFunctionName(toolCall.name)
        if serverID.isEmpty { return toolName }
        return "\(serverID) \u{00B7} \(toolName)"
    }

    private var durationText: String? {
        guard let seconds = toolResult?.durationSeconds, seconds > 0 else { return nil }
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return "\(Int(seconds.rounded()))s"
    }

    private var resolvedStatus: ToolCallStatus {
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

    private func statusColor(for status: ToolCallStatus) -> Color {
        switch status {
        case .running: return .secondary
        case .success: return .green
        case .error: return .red
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
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 1)) + "\u{2026}"
    }

    private enum ToolCallStatus {
        case running
        case success
        case error
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
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
        }
    }
}
