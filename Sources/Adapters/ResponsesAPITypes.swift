import Foundation

// MARK: - Shared Responses API Types
//
// These types are used by OpenAIAdapter, XAIAdapter, and OpenAIWebSocketAdapter
// for the OpenAI Responses API wire format.

struct ResponsesAPIFunctionCallState {
    let callID: String
    let name: String
    var argumentsBuffer: String = ""
}

struct ResponsesAPIUsageInfo: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let outputTokensDetails: OutputTokensDetails?
    let inputTokensDetails: InputTokensDetails?
    let promptTokensDetails: PromptTokensDetails?

    struct OutputTokensDetails: Codable {
        let reasoningTokens: Int?
    }

    struct InputTokensDetails: Codable {
        let cachedTokens: Int?
    }

    /// Backward compatibility for providers that still emit `prompt_tokens_details`.
    struct PromptTokensDetails: Codable {
        let cachedTokens: Int?
    }

    var cachedTokens: Int? {
        inputTokensDetails?.cachedTokens ?? promptTokensDetails?.cachedTokens
    }

    func toUsage() -> Usage? {
        guard let inputTokens, let outputTokens else { return nil }
        return Usage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            thinkingTokens: outputTokensDetails?.reasoningTokens,
            cachedTokens: cachedTokens
        )
    }
}

// MARK: - Streaming Event Types

struct ResponsesAPICreatedEvent: Codable {
    let response: ResponseInfo

    struct ResponseInfo: Codable {
        let id: String
    }
}

struct ResponsesAPIOutputTextDeltaEvent: Codable {
    let delta: String
}

struct ResponsesAPIReasoningTextDeltaEvent: Codable {
    let delta: String
}

struct ResponsesAPIReasoningSummaryTextDeltaEvent: Codable {
    let delta: String
}

struct ResponsesAPIFunctionCallArgumentsDeltaEvent: Codable {
    let itemId: String
    let delta: String
}

struct ResponsesAPIFunctionCallArgumentsDoneEvent: Codable {
    let itemId: String
    let arguments: String
}

struct ResponsesAPICompletedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let id: String?
        let citations: [String]?
        let output: [ResponsesAPIOutputItem]?
        let usage: ResponsesAPIUsageInfo?

        func toUsage() -> Usage? {
            usage?.toUsage()
        }
    }
}

struct ResponsesAPIFailedEvent: Codable {
    let response: Response

    struct Response: Codable {
        let error: ErrorInfo?

        struct ErrorInfo: Codable {
            let code: String?
            let message: String
        }
    }
}

// MARK: - Output Item Types

struct ResponsesAPIOutputContent: Codable {
    let type: String
    let text: String?
    let annotations: [ResponsesAPIOutputAnnotation]?
}

struct ResponsesAPIOutputAnnotation: Codable {
    let type: String
    let url: String?
    let title: String?
    let startIndex: Int?
    let endIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case title
        case startIndex
        case endIndex
        case urlCitation
    }

    private struct URLCitationPayload: Codable {
        let url: String?
        let title: String?
        let startIndex: Int?
        let endIndex: Int?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directType = try container.decodeIfPresent(String.self, forKey: .type)

        let directURL = try container.decodeIfPresent(String.self, forKey: .url)
        let directTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let directStartIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex)
        let directEndIndex = try container.decodeIfPresent(Int.self, forKey: .endIndex)
        let nestedCitation = try container.decodeIfPresent(URLCitationPayload.self, forKey: .urlCitation)

        if let directType = directType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directType.isEmpty {
            type = directType
        } else if nestedCitation != nil {
            type = "url_citation"
        } else {
            type = ""
        }

        url = directURL ?? nestedCitation?.url
        title = directTitle ?? nestedCitation?.title
        startIndex = directStartIndex ?? nestedCitation?.startIndex
        endIndex = directEndIndex ?? nestedCitation?.endIndex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(startIndex, forKey: .startIndex)
        try container.encodeIfPresent(endIndex, forKey: .endIndex)
    }
}

struct ResponsesAPIOutputItemAddedEvent: Codable {
    let outputIndex: Int?
    let sequenceNumber: Int?
    let item: Item

    struct Item: Codable {
        let id: String?
        let type: String
        let callId: String?
        let name: String?
        let status: String?
        let action: WebSearchAction?
        let content: [ResponsesAPIOutputContent]?
    }

    struct WebSearchAction: Codable {
        let type: String
        let query: String?
        let queries: [String]?
        let url: String?
        let pattern: String?
        let sources: [Source]?
    }

    struct Source: Codable {
        let type: String
        let url: String
        let title: String?
        let snippet: String?
        let description: String?
    }
}

struct ResponsesAPIOutputItemDoneEvent: Codable {
    let outputIndex: Int?
    let sequenceNumber: Int?
    let item: ResponsesAPIOutputItemAddedEvent.Item
}

struct ResponsesAPIWebSearchCallStatusEvent: Codable {
    let outputIndex: Int?
    let itemId: String
    let sequenceNumber: Int?
}

// MARK: - Output Item (used in non-streaming responses)

struct ResponsesAPIOutputItem: Codable {
    let id: String?
    let type: String
    let status: String?
    let action: ResponsesAPIOutputItemAddedEvent.WebSearchAction?
    let content: [ResponsesAPIOutputContent]?
    let summary: [ResponsesAPIOutputContent]?
}

// MARK: - Non-streaming Response

struct ResponsesAPIResponse: Codable {
    let id: String
    let output: [ResponsesAPIOutputItem]
    let citations: [String]?
    let usage: ResponsesAPIUsageInfo?

    var outputTextParts: [String] {
        output.flatMap { item in
            switch item.type {
            case "message":
                return item.content?.compactMap { $0.type == "output_text" ? $0.text : nil } ?? []
            case "reasoning":
                return item.summary?.compactMap { $0.type == "summary_text" ? $0.text : nil } ?? []
            default:
                return []
            }
        }
    }

    var searchActivities: [SearchActivity] {
        var out: [SearchActivity] = []

        for (index, item) in output.enumerated() {
            if item.type == "web_search_call",
               let id = item.id {
                out.append(
                    SearchActivity(
                        id: id,
                        type: item.action?.type ?? "web_search_call",
                        status: SearchActivityStatus(rawValue: item.status ?? "in_progress"),
                        arguments: ResponsesAPIResponse.searchActivityArguments(from: item.action),
                        outputIndex: index
                    )
                )
            }

            if item.type == "message" {
                let arguments = ResponsesAPIResponse.citationArguments(from: item.content)
                if !arguments.isEmpty {
                    let baseID = item.id ?? "message_\(index)"
                    out.append(
                        SearchActivity(
                            id: "\(baseID):citations",
                            type: "url_citation",
                            status: .completed,
                            arguments: arguments,
                            outputIndex: index
                        )
                    )
                }
            }
        }

        return out
    }

    static func searchActivityArguments(from action: ResponsesAPIOutputItemAddedEvent.WebSearchAction?) -> [String: AnyCodable] {
        guard let action else { return [:] }
        var out: [String: AnyCodable] = [:]
        if let query = action.query, !query.isEmpty {
            out["query"] = AnyCodable(query)
        }
        if let queries = action.queries, !queries.isEmpty {
            out["queries"] = AnyCodable(queries)
        }
        if let url = action.url, !url.isEmpty {
            out["url"] = AnyCodable(url)
        }
        if let pattern = action.pattern, !pattern.isEmpty {
            out["pattern"] = AnyCodable(pattern)
        }
        if let sources = action.sources, !sources.isEmpty {
            out["sources"] = AnyCodable(
                sources.map { source in
                    var payload: [String: Any] = [
                        "type": source.type,
                        "url": source.url
                    ]
                    if let title = source.title, !title.isEmpty {
                        payload["title"] = title
                    }
                    if let snippet = normalizedSearchPreviewText(source.snippet ?? source.description) {
                        payload["snippet"] = snippet
                    }
                    return payload
                }
            )
        }
        return out
    }

    static func citationArguments(from content: [ResponsesAPIOutputContent]?) -> [String: AnyCodable] {
        guard let content else { return [:] }

        var sourcePayloads: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for part in content where part.type == "output_text" {
            for annotation in part.annotations ?? [] {
                guard annotation.type == "url_citation" else { continue }
                guard let rawURL = annotation.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                    continue
                }

                let dedupeKey = rawURL.lowercased()
                guard !seenURLs.contains(dedupeKey) else { continue }
                seenURLs.insert(dedupeKey)

                var source: [String: Any] = [
                    "type": annotation.type,
                    "url": rawURL
                ]
                if let title = annotation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    source["title"] = title
                }
                if let snippet = citationPreviewSnippet(
                    text: part.text,
                    startIndex: annotation.startIndex,
                    endIndex: annotation.endIndex
                ) {
                    source["snippet"] = snippet
                }
                sourcePayloads.append(source)
            }
        }

        guard !sourcePayloads.isEmpty else { return [:] }

        var args: [String: AnyCodable] = [
            "sources": AnyCodable(sourcePayloads)
        ]
        if let firstSource = sourcePayloads.first,
           let firstURL = firstSource["url"] as? String {
            args["url"] = AnyCodable(firstURL)
            if let firstTitle = firstSource["title"] as? String, !firstTitle.isEmpty {
                args["title"] = AnyCodable(firstTitle)
            }
        }
        return args
    }

    func toUsage() -> Usage? {
        usage?.toUsage()
    }
}

// MARK: - Citation Utilities

func normalizedSearchPreviewText(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let collapsed = raw
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !collapsed.isEmpty else { return nil }
    if collapsed.count <= 420 {
        return collapsed
    }
    let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 420)
    return String(collapsed[..<endIndex]) + "\u{2026}"
}

func citationPreviewSnippet(
    text: String?,
    startIndex: Int?,
    endIndex: Int?
) -> String? {
    guard let text, !text.isEmpty else { return nil }
    guard let startIndex, let endIndex,
          startIndex >= 0, endIndex >= startIndex else {
        return nil
    }

    let textLength = text.count
    guard startIndex < textLength else { return nil }

    // OpenAI Responses annotations use character offsets with inclusive end_index.
    let clampedEnd = min(endIndex, textLength - 1)
    guard clampedEnd >= startIndex else { return nil }

    let contextRadius = 80
    let windowStart = max(0, startIndex - contextRadius)
    let windowEnd = min(textLength - 1, clampedEnd + contextRadius)
    guard windowEnd >= windowStart else { return nil }

    let snippetStart = text.index(text.startIndex, offsetBy: windowStart)
    let snippetEnd = text.index(text.startIndex, offsetBy: windowEnd)
    let snippet = String(text[snippetStart...snippetEnd])
    return normalizedSearchPreviewText(snippet)
}
