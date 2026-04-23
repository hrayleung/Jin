import Foundation

actor OpenRouterOCRClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!
        static let defaultMaxTokens = 8_192
        static let defaultPrompt = "Convert this page to Markdown. Preserve layout and tables. Return only the Markdown."
        static let validationPrompt = "Reply with exactly: OK"
        static let validationJPEGData = DeepInfraDeepSeekOCRClient.Constants.validationJPEGData
    }

    private let apiKey: String
    private let modelID: String
    private let baseURL: URL
    private let networkManager: NetworkManager

    init(
        apiKey: String,
        modelID: String = OpenRouterOCRModelCatalog.defaultModelID,
        baseURL: URL = Constants.defaultBaseURL,
        networkManager: NetworkManager = NetworkManager()
    ) {
        self.apiKey = apiKey
        self.modelID = OpenRouterOCRModelCatalog.normalizedModelID(modelID)
        self.baseURL = baseURL
        self.networkManager = networkManager
    }

    var selectedModel: OpenRouterOCRModelCatalog.Entry {
        OpenRouterOCRModelCatalog.resolvedEntry(for: modelID)
    }

    func validateAPIKey(timeoutSeconds: TimeInterval = 30) async throws {
        guard !Constants.validationJPEGData.isEmpty else {
            throw LLMError.invalidRequest(message: "Internal validation image missing.")
        }

        _ = try await ocrImage(
            Constants.validationJPEGData,
            mimeType: "image/jpeg",
            prompt: Constants.validationPrompt,
            maxTokens: 8,
            timeoutSeconds: timeoutSeconds
        )
    }

    func ocrImage(
        _ imageData: Data,
        mimeType: String,
        prompt: String = Constants.defaultPrompt,
        model: String? = nil,
        maxTokens: Int = Constants.defaultMaxTokens,
        temperature: Double = 0,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> String {
        let resolvedModelID = OpenRouterOCRModelCatalog.normalizedModelID(model ?? modelID)
        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"

        let body: [String: Any] = [
            "model": resolvedModelID,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": dataURL
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]

        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("chat/completions"),
            timeoutSeconds: timeoutSeconds,
            headers: Self.headers(apiKey: apiKey),
            body: body
        )

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(OpenRouterOCRChatCompletionResponse.self, from: data)
            let text = response.choices
                .compactMap { $0.message?.contentText }
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

    private static func headers(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Accept": "application/json",
            "HTTP-Referer": "https://jin.app",
            "X-Title": "Jin"
        ]
    }
}

private struct OpenRouterOCRChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: OpenRouterOCRMessageContent?

            var contentText: String? {
                content?.textValue
            }
        }

        let message: Message?
    }

    let choices: [Choice]
}

private enum OpenRouterOCRMessageContent: Decodable {
    case text(String)
    case parts([Part])

    struct Part: Decodable {
        let type: String?
        let text: String?
    }

    var textValue: String? {
        switch self {
        case .text(let value):
            return value
        case .parts(let parts):
            let text = parts
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let text = try? singleValueContainer.decode(String.self) {
            self = .text(text)
            return
        }
        self = .parts(try singleValueContainer.decode([Part].self))
    }
}
