import Foundation

actor DeepInfraDeepSeekOCRClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.deepinfra.com/v1/openai")!
        static let defaultModel = "deepseek-ai/DeepSeek-OCR"
        static let defaultMaxTokens = 4096

        static let defaultPrompt = """
Extract all text from the image(s) and return it as GitHub-flavored Markdown. \
Preserve layout where possible (headings, lists, tables). \
Return only the Markdown with no surrounding commentary.
"""

        // A tiny JPEG used for API key validation. Matches the JPEG format used for rendered PDF pages.
        static let validationJPEGBase64 = "/9j/4AAQSkZJRgABAQAASABIAAD/4QBARXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAAIKADAAQAAAABAAAAIAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAIAAgAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAgEBAgMCAgIDBAMDAwMEBQQEBAQEBQYFBQUFBQUGBgYGBgYGBgcHBwcHBwgICAgICQkJCQkJCQkJCf/bAEMBAQEBAgICBAICBAkGBQYJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCf/dAAQAAv/aAAwDAQACEQMRAD8A/v4ooooAKKKKAP/Q/v4ooooAKKKKAP/Z"
        static let validationJPEGData = Data(base64Encoded: validationJPEGBase64) ?? Data()
    }

    private let apiKey: String
    private let baseURL: URL
    private let networkManager: NetworkManager

    init(
        apiKey: String,
        baseURL: URL = Constants.defaultBaseURL,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.networkManager = networkManager
    }

    func validateAPIKey(timeoutSeconds: TimeInterval = 30) async throws {
        guard !Constants.validationJPEGData.isEmpty else {
            throw LLMError.invalidRequest(message: "Internal validation image missing.")
        }

        _ = try await ocrImages(
            [(data: Constants.validationJPEGData, mimeType: "image/jpeg")],
            prompt: "Reply with exactly: OK",
            maxTokens: 8,
            timeoutSeconds: timeoutSeconds
        )
    }

    func ocrImage(
        _ imageData: Data,
        mimeType: String,
        prompt: String = Constants.defaultPrompt,
        model: String = Constants.defaultModel,
        maxTokens: Int = Constants.defaultMaxTokens,
        temperature: Double = 0,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        try await ocrImages(
            [(data: imageData, mimeType: mimeType)],
            prompt: prompt,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            timeoutSeconds: timeoutSeconds
        )
    }

    func ocrImages(
        _ images: [(data: Data, mimeType: String)],
        prompt: String = Constants.defaultPrompt,
        model: String = Constants.defaultModel,
        maxTokens: Int = Constants.defaultMaxTokens,
        temperature: Double = 0,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let parts: [ChatContentPart] = images.map { image in
            let dataURL = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
            return .imageURL(dataURL)
        } + [.text(prompt)]

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "user", content: parts)
            ],
            maxTokens: maxTokens,
            temperature: temperature
        )

        let requestBody = try JSONEncoder().encode(body)

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ChatCompletionResponse.self, from: data)

            let text = response.choices
                .compactMap { $0.message?.content }
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let text, !text.isEmpty else {
                throw LLMError.decodingError(message: "Empty response content.")
            }

            return text
        } catch let error as LLMError {
            throw error
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: [ChatContentPart]
}

private enum ChatContentPart: Encodable {
    case imageURL(String)
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: url), forKey: .imageURL)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

private struct ImageURLPayload: Encodable {
    let url: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]
}
