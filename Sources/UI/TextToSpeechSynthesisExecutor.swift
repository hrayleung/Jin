import CoreGraphics
import Foundation

struct TextToSpeechQueuedClip: Sendable {
    let audioData: Data
    let duration: TimeInterval
    let waveformPeaks: [CGFloat]
}

enum TextToSpeechSynthesisExecutor {
    static let waveformSecondsPerPeak = TextToSpeechQueuedClipFactory.waveformSecondsPerPeak

    static func synthesize(
        text: String,
        config: TextToSpeechPlaybackManager.SynthesisConfig,
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void
    ) async throws {
        switch config {
        case .openai(let openAI):
            try await synthesizeOpenAI(text: text, config: openAI, onQueuedClip: onQueuedClip)
        case .openRouter(let openRouter):
            try await synthesizeOpenRouter(text: text, config: openRouter, onQueuedClip: onQueuedClip)
        case .groq(let groq):
            try await synthesizeGroq(text: text, config: groq, onQueuedClip: onQueuedClip)
        case .elevenlabs(let eleven):
            try await synthesizeElevenLabs(text: text, config: eleven, onQueuedClip: onQueuedClip)
        case .mimo(let mimo):
            try await synthesizeMiMo(text: text, config: mimo, onQueuedClip: onQueuedClip)
        }
    }

    private static func synthesizeOpenAI(
        text: String,
        config: TextToSpeechPlaybackManager.OpenAIConfig,
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.openAIPlan(
            text: text,
            responseFormat: config.responseFormat,
            instructions: config.instructions
        )
        let client = OpenAIAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await synthesizeQueuedClips(chunks: plan.chunks, onQueuedClip: onQueuedClip) { chunk in
            let clipData = try await client.createSpeech(
                input: chunk,
                model: config.model,
                voice: config.voice,
                responseFormat: plan.responseFormat,
                speed: config.speed,
                instructions: plan.instructions,
                streamFormat: nil
            )
            return TextToSpeechAudioDataNormalizer.openAIData(
                clipData,
                responseFormat: plan.responseFormat
            )
        }
    }

    private static func synthesizeOpenRouter(
        text: String,
        config: TextToSpeechPlaybackManager.OpenRouterConfig,
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.openAIPlan(
            text: text,
            responseFormat: config.responseFormat,
            instructions: config.instructions
        )
        let client = OpenRouterAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await synthesizeQueuedClips(chunks: plan.chunks, onQueuedClip: onQueuedClip) { chunk in
            let clipData = try await client.createSpeech(
                input: chunk,
                model: config.model,
                voice: config.voice,
                responseFormat: plan.responseFormat,
                speed: config.speed,
                instructions: plan.instructions
            )
            return TextToSpeechAudioDataNormalizer.openAIData(
                clipData,
                responseFormat: plan.responseFormat
            )
        }
    }

    private static func synthesizeGroq(
        text: String,
        config: TextToSpeechPlaybackManager.GroqConfig,
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void
    ) async throws {
        let plan = TextToSpeechSynthesisPlanSupport.groqPlan(text: text)
        let client = GroqAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await synthesizeQueuedClips(chunks: plan.chunks, onQueuedClip: onQueuedClip) { chunk in
            try await client.createSpeech(
                input: chunk,
                model: config.model,
                voice: config.voice,
                responseFormat: config.responseFormat
            )
        }
    }

    private static func synthesizeElevenLabs(
        text: String,
        config: TextToSpeechPlaybackManager.ElevenLabsConfig,
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void
    ) async throws {
        let plan = TextToSpeechSynthesisPlanSupport.elevenLabsPlan(text: text)
        let client = ElevenLabsTTSClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await synthesizeQueuedClips(chunks: plan.chunks, onQueuedClip: onQueuedClip) { chunk in
            let clipData = try await client.createSpeech(
                text: chunk,
                voiceId: config.voiceId,
                modelId: config.modelId,
                outputFormat: config.outputFormat,
                optimizeStreamingLatency: config.optimizeStreamingLatency,
                enableLogging: config.enableLogging,
                voiceSettings: config.voiceSettings
            )
            return TextToSpeechAudioDataNormalizer.elevenLabsData(
                clipData,
                outputFormat: config.outputFormat
            )
        }
    }

    private static func synthesizeMiMo(
        text: String,
        config: TextToSpeechPlaybackManager.MiMoConfig,
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.miMoPlan(
            text: text,
            responseFormat: config.responseFormat
        )
        let client = MiMoAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await synthesizeQueuedClips(chunks: plan.chunks, onQueuedClip: onQueuedClip) { chunk in
            let clipData = try await client.createSpeech(
                input: chunk,
                model: config.model,
                voice: config.voice,
                responseFormat: plan.responseFormat,
                styleInstruction: config.styleInstruction,
                voiceCloneSampleURL: config.voiceCloneSampleURL
            )
            return TextToSpeechAudioDataNormalizer.miMoData(
                clipData,
                responseFormat: plan.responseFormat
            )
        }
    }

    private static func synthesizeQueuedClips(
        chunks: [String],
        onQueuedClip: @escaping @MainActor (TextToSpeechQueuedClip) -> Void,
        makeAudioData: (String) async throws -> Data
    ) async throws {
        for chunk in chunks {
            try Task.checkCancellation()
            let clipData = try await makeAudioData(chunk)
            let clip = await TextToSpeechQueuedClipFactory.clip(fromAudioData: clipData)
            await onQueuedClip(clip)
        }
    }
}
