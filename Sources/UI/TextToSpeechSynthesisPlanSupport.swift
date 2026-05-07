import Foundation

enum TextToSpeechSynthesisPlanSupport {
    struct OpenAIPlan: Equatable {
        let responseFormat: String
        let chunks: [String]
        let instructions: String?
    }

    struct GroqPlan: Equatable {
        let chunks: [String]
    }

    struct ElevenLabsPlan: Equatable {
        let chunks: [String]
    }

    struct MiMoPlan: Equatable {
        let responseFormat: String
        let chunks: [String]
    }

    static func openAIPlan(
        text: String,
        responseFormat: String,
        instructions: String?
    ) throws -> OpenAIPlan {
        let format = try validatedResponseFormat(
            responseFormat,
            supportedFormats: supportedOpenAIPlaybackFormats,
            providerName: "OpenAI",
            supportedFormatDescription: "mp3, wav, aac, flac, or pcm"
        )

        return OpenAIPlan(
            responseFormat: format,
            chunks: chunks(for: text, maxCharacters: ChunkLimits.openAI),
            instructions: normalizedInstructions(instructions)
        )
    }

    static func groqPlan(text: String) -> GroqPlan {
        GroqPlan(chunks: chunks(for: text, maxCharacters: ChunkLimits.groq))
    }

    static func elevenLabsPlan(text: String) -> ElevenLabsPlan {
        ElevenLabsPlan(chunks: chunks(for: text, maxCharacters: ChunkLimits.elevenLabs))
    }

    static func miMoPlan(text: String, responseFormat: String) throws -> MiMoPlan {
        let format = try validatedResponseFormat(
            responseFormat,
            supportedFormats: MiMoModelIDs.textToSpeechResponseFormatSet,
            providerName: "MiMo",
            supportedFormatDescription: "wav, mp3, pcm, or pcm16"
        )

        return MiMoPlan(
            responseFormat: format,
            chunks: chunks(for: text, maxCharacters: ChunkLimits.miMo)
        )
    }

    private enum ChunkLimits {
        static let openAI = 4096
        static let groq = 200
        static let elevenLabs = 6000
        static let miMo = 4096
    }

    private static let supportedOpenAIPlaybackFormats: Set<String> = [
        "mp3",
        "wav",
        "aac",
        "flac",
        "pcm"
    ]

    private static func validatedResponseFormat(
        _ responseFormat: String,
        supportedFormats: Set<String>,
        providerName: String,
        supportedFormatDescription: String
    ) throws -> String {
        let format = normalized(responseFormat)
        guard supportedFormats.contains(format) else {
            throw LLMError.invalidRequest(
                message: "\(providerName) format “\(format)” is not playable in Jin. Choose \(supportedFormatDescription)."
            )
        }
        return format
    }

    private static func chunks(for text: String, maxCharacters: Int) -> [String] {
        TextToSpeechTextChunker.chunks(for: text, maxCharacters: maxCharacters)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmedLowercased
    }

    private static func normalizedInstructions(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmedNonEmpty == nil ? nil : value
    }
}
