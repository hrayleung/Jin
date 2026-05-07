import Foundation

enum ToolFunctionNameSupport {
    struct ParsedFunctionName: Equatable {
        let serverID: String
        let toolName: String
    }

    static func parse(_ name: String) -> ParsedFunctionName {
        guard let range = name.range(of: "__") else {
            return ParsedFunctionName(serverID: "", toolName: name)
        }

        let serverID = String(name[..<range.lowerBound])
        let toolName = String(name[range.upperBound...])
        return ParsedFunctionName(
            serverID: serverID,
            toolName: toolName.isEmpty ? name : toolName
        )
    }

    static func serverLabel(
        forServerID serverID: String,
        defaultLabel: String = "mcp"
    ) -> String {
        serverID.trimmedNonEmpty ?? defaultLabel
    }
}
