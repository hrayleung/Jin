import Foundation

enum TextToSpeechSynthesisPlanSupport {
    struct SynthesisPlan: Equatable {
        let responseFormat: String
        let chunks: [String]
        let instructions: String?
        /// Non-nil when this request should be streamed rather than buffered.
        let streaming: SpeechStreamingCapability?
    }

    /// Builds the request plan for one synthesis, resolving everything that varies per model:
    /// the playable response format, the per-model input length limit, whether `instructions`
    /// is accepted, and whether the request can stream.
    static func plan(
        text: String,
        provider: TextToSpeechProvider,
        model: String,
        responseFormat: String,
        instructions: String? = nil,
        streamingEnabled: Bool = false
    ) throws -> SynthesisPlan {
        let capabilities = SpeechModelCapabilityRegistry.synthesisCapabilities(
            provider: provider,
            modelID: model
        )

        let streaming = streamingEnabled ? capabilities.streaming : nil
        let resolvedFormat: String
        if let streaming {
            resolvedFormat = streaming.responseFormat
        } else {
            resolvedFormat = try validatedResponseFormat(
                responseFormat,
                supportedFormats: capabilities.responseFormats,
                providerName: provider.displayName
            )
        }

        return SynthesisPlan(
            responseFormat: resolvedFormat,
            chunks: TextToSpeechTextChunker.chunks(
                for: text,
                maxCharacters: capabilities.maxInputCharacters
            ),
            instructions: capabilities.supportsInstructions ? normalizedInstructions(instructions) : nil,
            streaming: streaming
        )
    }

    private static func validatedResponseFormat(
        _ responseFormat: String,
        supportedFormats: [String],
        providerName: String
    ) throws -> String {
        let format = responseFormat.trimmedLowercased
        guard supportedFormats.contains(format) else {
            throw LLMError.invalidRequest(
                message: "\(providerName) format “\(format)” is not playable in Jin. Choose \(describe(supportedFormats))."
            )
        }
        return format
    }

    private static func describe(_ formats: [String]) -> String {
        switch formats.count {
        case 0: return "a supported format"
        case 1: return formats[0]
        case 2: return "\(formats[0]) or \(formats[1])"
        default: return formats.dropLast().joined(separator: ", ") + ", or \(formats[formats.count - 1])"
        }
    }

    private static func normalizedInstructions(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmedNonEmpty == nil ? nil : value
    }
}
