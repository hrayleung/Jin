import Foundation

/// MCP tool calling controls (app-provided tools via MCP servers).
struct MCPToolsControls: Codable {
    var enabled: Bool
    /// Optional allowlist of MCP server IDs for this conversation. `nil` means "all enabled servers".
    var enabledServerIDs: [String]?

    init(enabled: Bool = true, enabledServerIDs: [String]? = nil) {
        self.enabled = enabled
        self.enabledServerIDs = enabledServerIDs
    }
}

/// Built-in web search controls (provider-native).
struct WebSearchControls: Codable {
    var enabled: Bool
    var contextSize: WebSearchContextSize?
    var sources: [WebSearchSource]?

    init(
        enabled: Bool = false,
        contextSize: WebSearchContextSize? = nil,
        sources: [WebSearchSource]? = nil
    ) {
        self.enabled = enabled
        self.contextSize = contextSize
        self.sources = sources
    }
}

enum WebSearchContextSize: String, Codable, CaseIterable {
    case low, medium, high

    var displayName: String { rawValue.capitalized }
}

enum WebSearchSource: String, Codable, CaseIterable {
    case web, x

    var displayName: String {
        switch self {
        case .web: return "Web"
        case .x: return "X"
        }
    }
}

/// How to process PDF attachments before sending to the model.
enum PDFProcessingMode: String, Codable, CaseIterable {
    case native
    case mistralOCR
    case deepSeekOCR
    case macOSExtract

    var displayName: String {
        switch self {
        case .native: return "Native"
        case .mistralOCR: return "Mistral OCR"
        case .deepSeekOCR: return "DeepSeek OCR (DeepInfra)"
        case .macOSExtract: return "macOS Extract"
        }
    }
}
