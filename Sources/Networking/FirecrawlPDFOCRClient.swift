import Foundation

actor FirecrawlPDFOCRClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.firecrawl.dev/v2")!
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

    func scrapePDF(
        at url: URL,
        mode: FirecrawlPDFParserMode,
        timeoutSeconds: TimeInterval = 180
    ) async throws -> String {
        let request = try NetworkRequestFactory.makeJSONRequest(
            url: baseURL.appendingPathComponent("scrape"),
            timeoutSeconds: timeoutSeconds,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ],
            body: [
                "url": url.absoluteString,
                "formats": ["markdown"],
                "parsers": [
                    [
                        "type": "pdf",
                        "mode": mode.rawValue
                    ]
                ],
                "storeInCache": false
            ]
        )

        let (data, _) = try await networkManager.sendRequest(request)
        let json = try decodeJSONObject(from: data)

        if let success = json["success"] as? Bool, !success {
            throw LLMError.invalidRequest(message: errorMessage(from: json))
        }

        let document = json["data"] as? [String: Any]
        let markdown = (document?["markdown"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let markdown, !markdown.isEmpty else {
            throw LLMError.decodingError(message: "Firecrawl scrape response did not contain markdown.")
        }

        return markdown
    }

    private func decodeJSONObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decodingError(message: "Expected Firecrawl JSON object response.")
        }
        return object
    }

    private func errorMessage(from json: [String: Any]) -> String {
        if let direct = firstString(in: json, keys: ["error", "message", "status"]),
           !direct.isEmpty {
            return direct
        }

        if let errors = json["errors"] as? [String], let first = errors.first, !first.isEmpty {
            return first
        }

        if let details = json["details"] as? String, !details.isEmpty {
            return details
        }

        return "Unknown Firecrawl error."
    }

    private func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
