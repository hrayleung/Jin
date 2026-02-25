import SwiftUI
import SwiftData

private struct MCPToolTimelineEntry: Identifiable {
    let call: ToolCall
    let result: ToolResult?

    var id: String { call.id }

    var status: ToolCallExecutionStatus {
        guard let result else { return .running }
        return result.isError ? .error : .success
    }
}

struct MCPToolTimelineView: View {
    let toolCalls: [ToolCall]
    let toolResultsByCallID: [String: ToolResult]
    let isStreaming: Bool

    @Query(sort: \MCPServerConfigEntity.name) private var configuredServers: [MCPServerConfigEntity]
    @State private var isExpanded = false

    init(
        toolCalls: [ToolCall],
        toolResultsByCallID: [String: ToolResult],
        isStreaming: Bool
    ) {
        self.toolCalls = toolCalls
        self.toolResultsByCallID = toolResultsByCallID
        self.isStreaming = isStreaming
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
            .onAppear {
                if isStreaming {
                    isExpanded = true
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                guard streaming else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0)) {
                    isExpanded = true
                }
            }
        }
    }

    // MARK: - Subviews

    private var collapsedSummaryRow: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: JinSpacing.small) {
                MCPIconView(iconID: summaryIconID, fallbackSystemName: "server.rack", size: 14)
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

                if let compactStatusText {
                    Text(compactStatusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                Text(expandedTitle)
                    .font(.headline)

                if let statusSummaryText {
                    Text("(\(statusSummaryText))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if shouldShowServerSummaryRow {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JinSpacing.xSmall) {
                        ForEach(serverIDs, id: \.self) { serverID in
                            Text(serverID)
                                .jinTagStyle()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ToolCallView(
                        toolCall: entry.call,
                        toolResult: entry.result,
                        showsConnectorAbove: index > 0,
                        showsConnectorBelow: index < entries.count - 1,
                        showsServerTag: shouldShowPerCallServerTag
                    )
                }
            }
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.top, JinSpacing.xSmall)
        .padding(.bottom, JinSpacing.xSmall)
    }

    // MARK: - Derived Content

    private var entries: [MCPToolTimelineEntry] {
        toolCalls.map { call in
            MCPToolTimelineEntry(call: call, result: toolResultsByCallID[call.id])
        }
    }

    private var runningCount: Int {
        entries.filter { $0.status == .running }.count
    }

    private var successCount: Int {
        entries.filter { $0.status == .success }.count
    }

    private var errorCount: Int {
        entries.filter { $0.status == .error }.count
    }

    private var totalDurationSeconds: Double? {
        let durations = entries.compactMap { $0.result?.durationSeconds }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    private var serverIDs: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for entry in entries {
            let serverID = parseFunctionName(entry.call.name).serverID
            let normalized = serverID.isEmpty ? "mcp" : serverID
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private var serverSummary: String {
        guard !serverIDs.isEmpty else { return "mcp" }
        let preview = serverIDs.prefix(2)
        let base = preview.joined(separator: ", ")
        if serverIDs.count > 2 {
            return "\(base) +\(serverIDs.count - 2)"
        }
        return base
    }

    private var shouldShowServerSummaryRow: Bool {
        serverIDs.count > 1
    }

    private var shouldShowPerCallServerTag: Bool {
        serverIDs.count > 1
    }

    private var summaryIconID: String {
        guard let serverID = serverIDs.first else {
            return MCPIconCatalog.defaultIconID
        }
        return resolvedIconID(forServerID: serverID)
    }

    private var iconIDByServerID: [String: String] {
        Dictionary(uniqueKeysWithValues: configuredServers.map { server in
            (server.id, server.resolvedMCPIconID)
        })
    }

    private func resolvedIconID(forServerID serverID: String) -> String {
        guard !serverID.isEmpty else { return MCPIconCatalog.defaultIconID }
        return iconIDByServerID[serverID] ?? MCPIconCatalog.defaultIconID
    }

    private var collapsedTitle: String {
        if runningCount > 0 {
            return "MCP \(serverSummary): \(runningCount) running"
        }

        if entries.count == 1 {
            let parsed = parseFunctionName(entries[0].call.name)
            if shouldShowPerCallServerTag {
                let serverID = parsed.serverID.isEmpty ? "mcp" : parsed.serverID
                return "\(serverID): \(parsed.toolName)"
            }
            return "MCP · \(parsed.toolName)"
        }

        return "MCP \(serverSummary): \(entries.count) calls"
    }

    private var expandedTitle: String {
        if serverIDs.count == 1, let singleServer = serverIDs.first {
            return singleServer.caseInsensitiveCompare("mcp") == .orderedSame
                ? (entries.count == 1 ? "Tool" : "Tools")
                : "Tools · \(singleServer)"
        }
        return entries.count == 1 ? "Tool" : "Tools"
    }

    private var compactStatusText: String? {
        if runningCount > 0 {
            return nil
        }

        if errorCount > 0 {
            if successCount > 0 {
                return "\(summaryCountText(successCount, singular: "ok", plural: "ok")) / \(summaryCountText(errorCount, singular: "failed", plural: "failed"))"
            }
            return summaryCountText(errorCount, singular: "failed", plural: "failed")
        }

        if successCount > 0 {
            return successCount == 1 ? "Succeeded" : "All succeeded"
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
        if let duration = totalDurationSeconds {
            if duration < 1 {
                parts.append("\(Int((duration * 1000).rounded()))ms")
            } else {
                parts.append("\(String(format: "%.1fs", duration))")
            }
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
                "\(entry.id):\(statusToken(for: entry.status))"
            }
            .joined(separator: "|")
    }

    private func statusToken(for status: ToolCallExecutionStatus) -> String {
        switch status {
        case .running: return "running"
        case .success: return "success"
        case .error: return "error"
        }
    }

    private func parseFunctionName(_ name: String) -> (serverID: String, toolName: String) {
        guard let split = name.range(of: "__") else { return ("", name) }
        let serverID = String(name[..<split.lowerBound])
        let toolName = String(name[split.upperBound...])
        return (serverID, toolName.isEmpty ? name : toolName)
    }

}
