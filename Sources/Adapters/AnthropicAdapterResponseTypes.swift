import Foundation

// MARK: - Anthropic Stream Event

struct AnthropicStreamEvent: Decodable {
    let type: String
    let message: MessageInfo?
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: Delta?
    let usage: UsageInfo?

    struct MessageInfo: Decodable {
        let id: String
        let type: String
        let role: String
        let model: String
        let usage: UsageInfo?
    }

    struct ContentBlock: Decodable {
        let type: String
        let id: String?
        let name: String?
        let signature: String?
        let data: String?
        let input: [String: AnyCodable]?
        let toolUseId: String?
        let webSearchResults: [WebSearchResult]?
        let citations: [TextCitation]?

        private enum CodingKeys: String, CodingKey {
            case type
            case id
            case name
            case signature
            case data
            case input
            case toolUseId
            case content
            case citations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            signature = try container.decodeIfPresent(String.self, forKey: .signature)
            data = try container.decodeIfPresent(String.self, forKey: .data)
            input = try container.decodeIfPresent([String: AnyCodable].self, forKey: .input)
            toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
            webSearchResults = try? container.decode([WebSearchResult].self, forKey: .content)
            citations = try? container.decode([TextCitation].self, forKey: .citations)
        }
    }

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let thinking: String?
        let signature: String?
        let partialJson: String?
    }

    struct UsageInfo: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let serviceTier: String?
        let inferenceGeo: String?
    }

    struct WebSearchResult: Decodable {
        let type: String?
        let title: String?
        let url: String?
        let snippet: String?
        let description: String?
    }

    struct TextCitation: Decodable {
        let type: String
        let url: String?
        let source: String?
        let title: String?
        let citedText: String?
    }
}

// MARK: - Usage Accumulator

struct AnthropicUsageAccumulator {
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheCreationInputTokens: Int?
    var cacheReadInputTokens: Int?
    var serviceTier: String?
    var inferenceGeo: String?

    mutating func merge(_ usage: AnthropicStreamEvent.UsageInfo?) {
        guard let usage else { return }
        if let inputTokens = usage.inputTokens {
            self.inputTokens = inputTokens
        }
        if let outputTokens = usage.outputTokens {
            self.outputTokens = outputTokens
        }
        if let cacheCreationInputTokens = usage.cacheCreationInputTokens {
            self.cacheCreationInputTokens = cacheCreationInputTokens
        }
        if let cacheReadInputTokens = usage.cacheReadInputTokens {
            self.cacheReadInputTokens = cacheReadInputTokens
        }
        if let serviceTier = usage.serviceTier {
            self.serviceTier = serviceTier
        }
        if let inferenceGeo = usage.inferenceGeo {
            self.inferenceGeo = inferenceGeo
        }
    }

    func toUsage() -> Usage? {
        guard inputTokens != nil
                || outputTokens != nil
                || cacheReadInputTokens != nil
                || cacheCreationInputTokens != nil else {
            return nil
        }

        return Usage(
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            cachedTokens: cacheReadInputTokens,
            cacheCreationTokens: cacheCreationInputTokens,
            cacheWriteTokens: cacheCreationInputTokens,
            serviceTier: serviceTier,
            inferenceGeo: inferenceGeo
        )
    }
}

// MARK: - Models List

struct AnthropicModelsListResponse: Codable {
    let data: [AnthropicModelInfo]
    let hasMore: Bool?
    let firstID: String?
    let lastID: String?

    struct AnthropicModelInfo: Codable {
        let id: String
        let displayName: String?
    }
}

// MARK: - Tool Call Builder

final class AnthropicToolCallBuilder {
    let id: String
    let name: String
    var argumentsBuffer = ""

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    func appendArguments(_ delta: String) {
        argumentsBuffer += delta
    }

    func build() -> ToolCall? {
        guard let data = argumentsBuffer.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let arguments = json.mapValues { AnyCodable($0) }
        return ToolCall(id: id, name: name, arguments: arguments)
    }
}

// MARK: - Search Activity Builder

final class AnthropicSearchActivityBuilder {
    let id: String
    let type: String
    private(set) var arguments: [String: AnyCodable]
    private var argumentsBuffer = ""

    init(id: String, type: String, arguments: [String: AnyCodable]) {
        self.id = id
        self.type = type
        self.arguments = arguments
    }

    func appendArguments(_ delta: String) {
        argumentsBuffer += delta
        guard let data = argumentsBuffer.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        for (key, value) in json {
            arguments[key] = AnyCodable(value)
        }
        argumentsBuffer = ""
    }

    func build(status: SearchActivityStatus, outputIndex: Int?) -> SearchActivity? {
        SearchActivity(
            id: id,
            type: type,
            status: status,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }
}
