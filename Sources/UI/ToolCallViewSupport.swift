import Foundation

enum ToolCallViewSupport {
    private static let preferredSummaryKeys = ["query", "q", "url", "input", "text"]

    struct ParsedFunctionName: Equatable {
        let serverID: String
        let toolName: String
    }

    static func formattedArgumentsJSON(for arguments: [String: AnyCodable]) -> String? {
        ToolArgumentPresentationSupport.formattedJSON(for: arguments, allowsEmpty: true)
    }

    static func parseFunctionName(_ name: String) -> ParsedFunctionName {
        let parsedName = ToolFunctionNameSupport.parse(name)
        return ParsedFunctionName(
            serverID: parsedName.serverID,
            toolName: parsedName.toolName
        )
    }

    static func serverLabel(for parsedName: ParsedFunctionName) -> String {
        ToolFunctionNameSupport.serverLabel(forServerID: parsedName.serverID)
    }

    static func durationText(for seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return "\(Int(seconds.rounded()))s"
    }

    static func executionStatus(for result: ToolResult?) -> ToolCallExecutionStatus {
        guard let result else { return .running }
        return result.isError ? .error : .success
    }

    static func argumentSummary(
        for arguments: [String: AnyCodable],
        maxLength: Int = 200
    ) -> String? {
        ToolArgumentPresentationSupport.summary(
            for: arguments,
            preferredKeys: preferredSummaryKeys,
            maxLength: maxLength,
            fallsBackToJSON: true
        )
    }

    static func statusLabel(for status: ToolCallExecutionStatus) -> String {
        ToolTimelineTextSupport.statusLabel(for: status)
    }

    static func oneLine(_ string: String, maxLength: Int) -> String {
        ToolTimelineTextSupport.oneLine(string, maxLength: maxLength)
    }
}
