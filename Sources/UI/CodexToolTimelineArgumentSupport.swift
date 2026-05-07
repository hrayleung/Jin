import Foundation

extension CodexToolTimelineSupport {
    private static let preferredArgumentSummaryKeys = [
        "command",
        "cmd",
        "path",
        "file",
        "filePath",
        "file_path",
        "query",
        "input",
        "text",
        "content"
    ]

    static func formattedArgumentsJSON(for arguments: [String: AnyCodable]) -> String? {
        ToolArgumentPresentationSupport.formattedJSON(for: arguments)
    }

    static func argumentSummary(
        for arguments: [String: AnyCodable],
        maxLength: Int = 200
    ) -> String? {
        ToolArgumentPresentationSupport.summary(
            for: arguments,
            preferredKeys: preferredArgumentSummaryKeys,
            maxLength: maxLength,
            fallsBackToJSON: true
        )
    }
}
