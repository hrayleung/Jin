import Collections
import Foundation

extension MCPToolTimelineSupport {
    static func serverIDs(for entries: [Entry]) -> [String] {
        var ordered = OrderedSet<String>()

        for entry in entries {
            ordered.append(normalizedServerID(for: entry.call.name))
        }

        return Array(ordered)
    }

    static func serverSummary(for serverIDs: [String]) -> String {
        let normalizedServerIDs = normalizedServerIDs(for: serverIDs)
        guard !normalizedServerIDs.isEmpty else { return "mcp" }
        let preview = normalizedServerIDs.prefix(2)
        let base = preview.joined(separator: ", ")
        if normalizedServerIDs.count > 2 {
            return "\(base) +\(normalizedServerIDs.count - 2)"
        }
        return base
    }

    static func shouldShowServerSummaryRow(for serverIDs: [String]) -> Bool {
        normalizedServerIDs(for: serverIDs).count > 1
    }

    static func shouldShowPerCallServerTag(for serverIDs: [String]) -> Bool {
        normalizedServerIDs(for: serverIDs).count > 1
    }

    static func resolvedIconID(
        forServerID serverID: String,
        iconIDByServerID: [String: String],
        defaultIconID: String
    ) -> String {
        guard let normalizedServerID = serverID.trimmedNonEmpty else { return defaultIconID }
        return iconIDByServerID[normalizedServerID] ?? defaultIconID
    }

    static func summaryIconID(
        for serverIDs: [String],
        iconIDByServerID: [String: String],
        defaultIconID: String
    ) -> String {
        guard let serverID = normalizedServerIDs(for: serverIDs).first else { return defaultIconID }
        return resolvedIconID(
            forServerID: serverID,
            iconIDByServerID: iconIDByServerID,
            defaultIconID: defaultIconID
        )
    }

    static func iconStackLayout(
        for serverIDs: [String],
        maxVisibleCount: Int = 4,
        iconFrameSize: Double = 16,
        overlapOffset: Double = 10
    ) -> IconStackLayout {
        let displayed = Array(normalizedServerIDs(for: serverIDs).prefix(max(0, maxVisibleCount)))
        let visibleCount = displayed.count
        let totalWidth = visibleCount == 0
            ? 0
            : iconFrameSize + overlapOffset * Double(visibleCount - 1)

        return IconStackLayout(
            displayedServerIDs: displayed,
            iconFrameSize: iconFrameSize,
            overlapOffset: overlapOffset,
            totalWidth: totalWidth
        )
    }

    static func normalizedServerIDs(for serverIDs: [String]) -> [String] {
        var ordered = OrderedSet<String>()

        for serverID in serverIDs {
            ordered.append(ToolFunctionNameSupport.serverLabel(forServerID: serverID))
        }

        return Array(ordered)
    }

    static func parseFunctionName(_ name: String) -> ParsedFunctionName {
        let parsedName = ToolFunctionNameSupport.parse(name)
        return ParsedFunctionName(
            serverID: parsedName.serverID,
            toolName: parsedName.toolName
        )
    }

    private static func normalizedServerID(for toolName: String) -> String {
        let serverID = parseFunctionName(toolName).serverID
        return ToolFunctionNameSupport.serverLabel(forServerID: serverID)
    }
}
