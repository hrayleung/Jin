import Foundation

enum TextToSpeechAudioDataNormalizer {
    static func openAIData(_ data: Data, responseFormat: String) -> Data {
        let format = normalized(responseFormat)
        guard format == "pcm" else { return data }

        // OpenAI `pcm` responses are raw 16-bit signed little-endian PCM at 24kHz.
        return TextToSpeechWAVContainer.wrapPCM16LEMono(pcmData: data, sampleRate: 24_000)
    }

    static func elevenLabsData(_ data: Data, outputFormat: String?) -> Data {
        let format = normalized(outputFormat ?? "")
        guard format.hasPrefix("pcm_") else { return data }

        let sampleRateText = format.replacingOccurrences(of: "pcm_", with: "")
        guard let sampleRate = Int(sampleRateText), sampleRate > 0 else { return data }

        return TextToSpeechWAVContainer.wrapPCM16LEMono(pcmData: data, sampleRate: sampleRate)
    }

    static func miMoData(_ data: Data, responseFormat: String) -> Data {
        let format = normalized(responseFormat)
        guard format == "pcm" || format == "pcm16" else { return data }
        return TextToSpeechWAVContainer.wrapPCM16LEMono(pcmData: data, sampleRate: 24_000)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmedLowercased
    }
}
