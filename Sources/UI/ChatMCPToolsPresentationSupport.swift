import Foundation

extension ChatAuxiliaryControlSupport {
    static func mcpToolsHelpText(
        supportsMCPToolsControl: Bool,
        isMCPToolsEnabled: Bool,
        selectedServerCount: Int
    ) -> String {
        guard supportsMCPToolsControl else { return "MCP Tools: Not supported" }
        guard isMCPToolsEnabled else { return "MCP Tools: Off" }
        if selectedServerCount == 0 { return "MCP Tools: On (no servers)" }
        return "MCP Tools: On (\(selectedServerCount) server\(selectedServerCount == 1 ? "" : "s"))"
    }

    static func mcpToolsBadgeText(
        supportsMCPToolsControl: Bool,
        isMCPToolsEnabled: Bool,
        selectedServerCount: Int
    ) -> String? {
        guard supportsMCPToolsControl, isMCPToolsEnabled, selectedServerCount > 0 else { return nil }
        return selectedServerCount > 99 ? "99+" : "\(selectedServerCount)"
    }
}
