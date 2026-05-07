import Foundation

/// Tool call from LLM
struct ToolCall: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]
    let signature: String?
    let providerContext: [String: String]?

    init(
        id: String,
        name: String,
        arguments: [String: AnyCodable],
        signature: String? = nil,
        providerContext: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.signature = signature
        self.providerContext = providerContext
    }

    func providerContextValue(for key: String) -> String? {
        providerContext?[key]
    }
}

/// Result from tool execution
struct ToolResult: Codable, Identifiable, Sendable {
    let id: String
    let toolCallID: String
    let toolName: String?
    let content: String
    let isError: Bool
    let signature: String?
    let durationSeconds: Double?
    let rawOutputPath: String?

    init(
        id: String = UUID().uuidString,
        toolCallID: String,
        toolName: String? = nil,
        content: String,
        isError: Bool = false,
        signature: String? = nil,
        durationSeconds: Double? = nil,
        rawOutputPath: String? = nil
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.content = content
        self.isError = isError
        self.signature = signature
        self.durationSeconds = durationSeconds
        self.rawOutputPath = rawOutputPath
    }
}
