import Foundation

extension AgentToolTimelineSupport {
    private static let preferredArgumentSummaryKeys = [
        "command",
        "cmd",
        "path",
        "file",
        "filePath",
        "file_path",
        "pattern",
        "query"
    ]

    static func argumentSummary(
        for arguments: [String: AnyCodable],
        maxLength: Int = 120
    ) -> String? {
        ToolArgumentPresentationSupport.summary(
            for: arguments,
            preferredKeys: preferredArgumentSummaryKeys,
            maxLength: maxLength,
            fallsBackToJSON: false
        )
    }

    static func formattedArgumentsJSON(for arguments: [String: AnyCodable]) -> String? {
        ToolArgumentPresentationSupport.formattedJSON(for: arguments)
    }
}
