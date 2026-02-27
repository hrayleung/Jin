import Foundation

/// Shared Codable response type for both Gemini and Vertex AI
/// generateContent / streamGenerateContent endpoints.
///
/// Gemini and Vertex AI return nearly identical JSON structures for content generation.
/// This shared type eliminates duplication while handling minor differences via optional fields.
struct GoogleGenerateContentResponse: Codable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let usageMetadata: UsageMetadata?
    let groundingMetadata: GroundingMetadata?

    struct Candidate: Codable {
        let content: Content?
        let finishReason: String?
        let groundingMetadata: GroundingMetadata?
    }

    struct Content: Codable {
        let parts: [Part]?
        let role: String?
    }

    struct Part: Codable {
        let text: String?
        let thought: Bool?
        let thoughtSignature: String?
        let functionCall: FunctionCall?
        let functionResponse: FunctionResponse?
        let inlineData: InlineData?
    }

    struct InlineData: Codable {
        let mimeType: String?
        let data: String?
    }

    struct FunctionCall: Codable {
        let name: String
        let args: [String: AnyCodable]?
    }

    struct FunctionResponse: Codable {
        let name: String?
        let response: [String: AnyCodable]?
    }

    struct PromptFeedback: Codable {
        let blockReason: String?
    }

    struct UsageMetadata: Codable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
        let cachedContentTokenCount: Int?
    }

    struct GroundingMetadata: Codable {
        let webSearchQueries: [String]?
        let retrievalQueries: [String]?
        let groundingChunks: [GroundingChunk]?
        let groundingSupports: [GroundingSupport]?
        let searchEntryPoint: SearchEntryPoint?

        struct GroundingChunk: Codable {
            let web: WebChunk?

            struct WebChunk: Codable {
                let uri: String?
                let title: String?
            }
        }

        struct SearchEntryPoint: Codable {
            let renderedContent: String?
            let sdkBlob: String?
        }

        struct GroundingSupport: Codable {
            let segment: Segment?
            let groundingChunkIndices: [Int]?

            struct Segment: Codable {
                let text: String?
            }
        }
    }

    func toUsage() -> Usage? {
        guard let usageMetadata else { return nil }
        guard let input = usageMetadata.promptTokenCount,
              let output = usageMetadata.candidatesTokenCount else {
            return nil
        }
        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: nil,
            cachedTokens: usageMetadata.cachedContentTokenCount
        )
    }
}
