import Foundation

struct OpenAIModelsResponse: Codable {
    let data: [Model]

    struct Model: Codable {
        let id: String
        let name: String?
        let contextWindow: Int?
        let maxTokens: Int?
        let type: String?
        let tags: [String]?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case contextWindow = "context_window"
            case maxTokens = "max_tokens"
            case type
            case tags
        }
    }
}
