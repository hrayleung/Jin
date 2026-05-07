import Foundation

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
        case urlCitationSnake = "url_citation"
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
            ?? container.decodeIfPresent(URLCitationPayload.self, forKey: .urlCitationSnake)

        if let directType = directType?.trimmedNonEmpty {
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
        // Code interpreter fields
        let code: String?
        let containerId: String?
        let outputs: [CodeInterpreterOutput]?
    }

    struct CodeInterpreterOutput: Codable {
        let type: String
        let logs: String?
        let url: String?
        // Image output may use image_url or url
        let imageUrl: String?
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

// MARK: - Output Item (used in non-streaming responses)

struct ResponsesAPIOutputItem: Codable {
    let id: String?
    let type: String
    let status: String?
    let action: ResponsesAPIOutputItemAddedEvent.WebSearchAction?
    let content: [ResponsesAPIOutputContent]?
    let summary: [ResponsesAPIOutputContent]?
    // Code interpreter fields
    let code: String?
    let containerId: String?
    let outputs: [ResponsesAPIOutputItemAddedEvent.CodeInterpreterOutput]?
}
