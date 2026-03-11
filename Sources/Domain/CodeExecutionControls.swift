import Foundation

/// Controls for provider-native code execution tools.
struct CodeExecutionControls: Codable {
    var enabled: Bool

    /// OpenAI-specific: container configuration for code interpreter.
    var container: CodeExecutionContainer?

    init(enabled: Bool = false, container: CodeExecutionContainer? = nil) {
        self.enabled = enabled
        self.container = container
    }
}

/// OpenAI code interpreter container configuration.
struct CodeExecutionContainer: Codable {
    /// Container type. Defaults to "auto".
    var type: String?
    /// Memory limit (e.g., "1g", "4g"). Defaults to "1g".
    var memoryLimit: String?

    init(type: String? = nil, memoryLimit: String? = nil) {
        self.type = type
        self.memoryLimit = memoryLimit
    }
}
