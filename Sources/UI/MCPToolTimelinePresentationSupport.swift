import Foundation

extension MCPToolTimelineSupport {
    static func collapsedTitle(
        for entries: [Entry],
        serverIDs: [String]? = nil
    ) -> String {
        let resolvedServerIDs = normalizedServerIDs(for: serverIDs ?? self.serverIDs(for: entries))
        let counts = counts(for: entries)
        let summary = serverSummary(for: resolvedServerIDs)

        if counts.running > 0 {
            return "MCP \(summary): \(counts.running) running"
        }

        if entries.count == 1 {
            let parsed = parseFunctionName(entries[0].call.name)
            if shouldShowPerCallServerTag(for: resolvedServerIDs) {
                let serverID = ToolFunctionNameSupport.serverLabel(forServerID: parsed.serverID)
                return "\(serverID): \(parsed.toolName)"
            }
            return "MCP · \(parsed.toolName)"
        }

        return "MCP \(summary): \(entries.count) calls"
    }

    static func expandedTitle(
        for entries: [Entry],
        serverIDs: [String]? = nil
    ) -> String {
        let resolvedServerIDs = normalizedServerIDs(for: serverIDs ?? self.serverIDs(for: entries))
        if resolvedServerIDs.count == 1, let singleServer = resolvedServerIDs.first {
            return singleServer.caseInsensitiveCompare("mcp") == .orderedSame
                ? (entries.count == 1 ? "Tool" : "Tools")
                : "Tools · \(singleServer)"
        }
        return entries.count == 1 ? "Tool" : "Tools"
    }

    static func compactStatusBadges(for entries: [Entry]) -> [CompactStatusBadge] {
        let counts = counts(for: entries)
        guard counts.running == 0 else { return [] }

        var badges: [CompactStatusBadge] = []

        if counts.succeeded > 0 {
            badges.append(CompactStatusBadge(
                count: counts.succeeded,
                icon: "checkmark.circle.fill",
                tone: .success
            ))
        }
        if counts.failed > 0 {
            badges.append(CompactStatusBadge(
                count: counts.failed,
                icon: "xmark.circle.fill",
                tone: .failure
            ))
        }

        return badges
    }

    static func statusSummaryText(for entries: [Entry]) -> String? {
        let counts = counts(for: entries)
        var parts: [String] = []

        if counts.succeeded > 0 {
            parts.append(summaryCountText(counts.succeeded, singular: "passed", plural: "passed"))
        }
        if counts.failed > 0 {
            parts.append(summaryCountText(counts.failed, singular: "failed", plural: "failed"))
        }
        if counts.running > 0 {
            parts.append(summaryCountText(counts.running, singular: "running", plural: "running"))
        }
        if let duration = totalDurationSeconds(for: entries) {
            if duration < 1 {
                parts.append("\(Int((duration * 1000).rounded()))ms")
            } else {
                parts.append("\(String(format: "%.1fs", duration))")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func summaryCountText(_ count: Int, singular: String, plural: String) -> String {
        ToolTimelineTextSupport.summaryCountText(count, singular: singular, plural: plural)
    }
}
