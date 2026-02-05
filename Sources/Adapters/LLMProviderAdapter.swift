import Foundation

/// Streaming reasoning delta (provider-specific details are optional)
enum ThinkingDelta: Sendable {
    case thinking(textDelta: String, signature: String?)
    case redacted(data: String)
}

/// Stream event from LLM provider (normalized)
enum StreamEvent: Sendable {
    case messageStart(id: String)
    case contentDelta(ContentPart) // Incremental text/image
    case thinkingDelta(ThinkingDelta) // Reasoning output
    case toolCallStart(ToolCall)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCallEnd(ToolCall)
    case messageEnd(usage: Usage?)
    case error(LLMError)
}

/// LLM errors (normalized across providers)
enum LLMError: Error, LocalizedError {
    case authenticationFailed(message: String?)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case invalidRequest(message: String)
    case contentFiltered // Safety/moderation
    case networkError(underlying: Error)
    case providerError(code: String, message: String)
    case decodingError(message: String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return "Authentication failed. Please check your API key."
            }
            return "Authentication failed. Please check your API key.\n\n\(trimmed)"
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter {
                return "Rate limit exceeded. Retry after \(Int(retryAfter)) seconds."
            }
            return "Rate limit exceeded."
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .contentFiltered:
            return "Content was filtered by the provider's safety system."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .providerError(let code, let message):
            return "Provider error (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        }
    }
}

/// Provider adapter protocol
protocol LLMProviderAdapter: Actor {
    var providerConfig: ProviderConfig { get }
    var capabilities: ModelCapability { get }

    /// Send message and receive streaming events
    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>

    /// Validate API key
    func validateAPIKey(_ key: String) async throws -> Bool

    /// Fetch available models (if supported by provider)
    func fetchAvailableModels() async throws -> [ModelInfo]

    /// Translate tools to provider-specific format
    func translateTools(_ tools: [ToolDefinition]) -> Any
}

/// Conversation model
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var systemPrompt: String?
    var messages: [Message]
    var modelConfig: ModelConfig
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        systemPrompt: String? = nil,
        messages: [Message] = [],
        modelConfig: ModelConfig,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.modelConfig = modelConfig
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
