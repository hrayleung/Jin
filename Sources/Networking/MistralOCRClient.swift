import Foundation

actor MistralOCRClient {
    enum Constants {
        static let defaultBaseURL = URL(string: "https://api.mistral.ai/v1")!
        static let defaultModel = "mistral-ocr-latest"
    }

    struct OCRResponse: Decodable {
        struct OCRImage: Decodable {
            let id: String
            let imageBase64: String?

            enum CodingKeys: String, CodingKey {
                case id
                case imageBase64 = "image_base64"
            }
        }

        struct OCRTable: Decodable {
            let id: String
            let content: String?

            enum CodingKeys: String, CodingKey {
                case id
                case html
                case markdown
                case content
                case table
                case data
                case tableHTML = "table_html"
                case tableMarkdown = "table_markdown"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)

                let markdown = try container.decodeIfPresent(String.self, forKey: .markdown)
                let html = try container.decodeIfPresent(String.self, forKey: .html)
                let contentValue = try container.decodeIfPresent(String.self, forKey: .content)
                let table = try container.decodeIfPresent(String.self, forKey: .table)
                let data = try container.decodeIfPresent(String.self, forKey: .data)
                let tableMarkdown = try container.decodeIfPresent(String.self, forKey: .tableMarkdown)
                let tableHTML = try container.decodeIfPresent(String.self, forKey: .tableHTML)

                content = markdown ?? html ?? contentValue ?? table ?? data ?? tableMarkdown ?? tableHTML
            }
        }

        struct Page: Decodable {
            let index: Int
            let markdown: String
            let images: [OCRImage]?
            let tables: [OCRTable]?
        }

        let pages: [Page]
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

    func validateAPIKey() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        _ = try await networkManager.sendRequest(request)
    }

    func ocrPDF(
        _ pdfData: Data,
        model: String = Constants.defaultModel,
        includeImageBase64: Bool = false,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> OCRResponse {
        let dataURL = "data:application/pdf;base64,\(pdfData.base64EncodedString())"

        let body = OCRRequest(
            model: model,
            document: OCRDocument(
                type: "document_url",
                documentURL: dataURL
            ),
            includeImageBase64: includeImageBase64
        )

        let requestBody = try JSONEncoder().encode(body)

        var request = URLRequest(url: baseURL.appendingPathComponent("ocr"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody

        let (data, _) = try await networkManager.sendRequest(request)
        do {
            return try JSONDecoder().decode(OCRResponse.self, from: data)
        } catch {
            let message = String(data: data, encoding: .utf8) ?? error.localizedDescription
            throw LLMError.decodingError(message: message)
        }
    }
}

private struct OCRRequest: Encodable {
    let model: String
    let document: OCRDocument
    let includeImageBase64: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case document
        case includeImageBase64 = "include_image_base64"
    }
}

private struct OCRDocument: Encodable {
    let type: String
    let documentURL: String

    enum CodingKeys: String, CodingKey {
        case type
        case documentURL = "document_url"
    }
}
