import CoreGraphics
import Foundation

struct TextToSpeechQueuedClip: Sendable {
    let audioData: Data
    let duration: TimeInterval
    let waveformPeaks: [CGFloat]
}

/// What one synthesis produces, in arrival order.
///
/// Buffered providers emit `.clip` per text chunk; streaming providers emit `.streamStarted`
/// once and then `.streamedPCM` for every chunk of 16-bit mono PCM that arrives.
enum TextToSpeechSynthesisEvent: Sendable {
    case clip(TextToSpeechQueuedClip)
    case streamStarted(sampleRate: Double)
    case streamedPCM(Data)
}

enum TextToSpeechSynthesisExecutor {
    static let waveformSecondsPerPeak = TextToSpeechQueuedClipFactory.waveformSecondsPerPeak

    static func synthesize(
        text: String,
        config: TextToSpeechPlaybackManager.SynthesisConfig,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        switch config {
        case .openai(let openAI):
            try await synthesizeOpenAI(text: text, config: openAI, onEvent: onEvent)
        case .openRouter(let openRouter):
            try await synthesizeOpenRouter(text: text, config: openRouter, onEvent: onEvent)
        case .groq(let groq):
            try await synthesizeGroq(text: text, config: groq, onEvent: onEvent)
        case .mistral(let mistral):
            try await synthesizeMistral(text: text, config: mistral, onEvent: onEvent)
        case .elevenlabs(let eleven):
            try await synthesizeElevenLabs(text: text, config: eleven, onEvent: onEvent)
        case .mimo(let mimo):
            try await synthesizeMiMo(text: text, config: mimo, onEvent: onEvent)
        }
    }

    private static func synthesizeOpenAI(
        text: String,
        config: TextToSpeechPlaybackManager.OpenAIConfig,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: text,
            provider: .openai,
            model: config.model,
            responseFormat: config.responseFormat,
            instructions: config.instructions,
            streamingEnabled: config.streamingEnabled
        )
        let client = OpenAIAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        if let streaming = plan.streaming {
            try await streamChunks(plan: plan, streaming: streaming, onEvent: onEvent) { chunk in
                try await client.createSpeechStream(
                    input: chunk,
                    model: config.model,
                    voice: config.voice,
                    responseFormat: streaming.responseFormat,
                    speed: config.speed,
                    instructions: plan.instructions
                )
            }
            return
        }

        try await queueChunks(plan: plan, onEvent: onEvent) { chunk in
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
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: text,
            provider: .openRouter,
            model: config.model,
            responseFormat: config.responseFormat
        )
        let client = OpenRouterAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await queueChunks(plan: plan, onEvent: onEvent) { chunk in
            let clipData = try await client.createSpeech(
                input: chunk,
                model: config.model,
                voice: config.voice,
                responseFormat: plan.responseFormat
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
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: text,
            provider: .groq,
            model: config.model,
            responseFormat: config.responseFormat
        )
        let client = GroqAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await queueChunks(plan: plan, onEvent: onEvent) { chunk in
            try await client.createSpeech(
                input: chunk,
                model: config.model,
                voice: config.voice,
                responseFormat: plan.responseFormat
            )
        }
    }

    private static func synthesizeMistral(
        text: String,
        config: TextToSpeechPlaybackManager.MistralConfig,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: text,
            provider: .mistral,
            model: config.model,
            responseFormat: config.responseFormat
        )
        let client = MistralTTSClient(apiKey: config.apiKey, baseURL: config.baseURL)

        try await queueChunks(plan: plan, onEvent: onEvent) { chunk in
            // Every format Mistral offers here is self-describing (mp3/wav/flac), so unlike
            // the OpenAI path there is no headerless PCM to wrap.
            try await client.createSpeech(
                input: chunk,
                model: config.model,
                voiceId: config.voiceId,
                responseFormat: plan.responseFormat
            )
        }
    }

    private static func synthesizeElevenLabs(
        text: String,
        config: TextToSpeechPlaybackManager.ElevenLabsConfig,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        let modelID = config.modelId?.trimmedNonEmpty
            ?? SpeechProviderModelCatalog.defaultElevenLabsTextToSpeechModelID
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: text,
            provider: .elevenlabs,
            model: modelID,
            responseFormat: config.outputFormat?.trimmedNonEmpty ?? "mp3_44100_128",
            streamingEnabled: config.streamingEnabled
        )
        let client = ElevenLabsTTSClient(apiKey: config.apiKey, baseURL: config.baseURL)

        if let streaming = plan.streaming {
            try await streamChunks(plan: plan, streaming: streaming, onEvent: onEvent) { chunk in
                try await client.createSpeechStream(
                    text: chunk,
                    voiceId: config.voiceId,
                    // The plan's chunk limit was resolved from `modelID`, so the request has
                    // to name the same model or the server would fall back to another one.
                    modelId: modelID,
                    outputFormat: streaming.responseFormat,
                    optimizeStreamingLatency: config.optimizeStreamingLatency,
                    enableLogging: config.enableLogging,
                    voiceSettings: config.voiceSettings
                )
            }
            return
        }

        try await queueChunks(plan: plan, onEvent: onEvent) { chunk in
            let clipData = try await client.createSpeech(
                text: chunk,
                voiceId: config.voiceId,
                modelId: modelID,
                outputFormat: plan.responseFormat,
                optimizeStreamingLatency: config.optimizeStreamingLatency,
                enableLogging: config.enableLogging,
                voiceSettings: config.voiceSettings
            )
            return TextToSpeechAudioDataNormalizer.elevenLabsData(
                clipData,
                outputFormat: plan.responseFormat
            )
        }
    }

    private static func synthesizeMiMo(
        text: String,
        config: TextToSpeechPlaybackManager.MiMoConfig,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void
    ) async throws {
        let plan = try TextToSpeechSynthesisPlanSupport.plan(
            text: text,
            provider: .xiaomiMiMo,
            model: config.model,
            responseFormat: config.responseFormat,
            streamingEnabled: config.streamingEnabled
        )
        let client = MiMoAudioClient(apiKey: config.apiKey, baseURL: config.baseURL)

        if let streaming = plan.streaming {
            try await streamChunks(plan: plan, streaming: streaming, onEvent: onEvent) { chunk in
                try await client.createSpeechStream(
                    input: chunk,
                    model: config.model,
                    voice: config.voice,
                    responseFormat: streaming.responseFormat,
                    styleInstruction: config.styleInstruction,
                    voiceCloneSampleURL: config.voiceCloneSampleURL
                )
            }
            return
        }

        try await queueChunks(plan: plan, onEvent: onEvent) { chunk in
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

    private static func queueChunks(
        plan: TextToSpeechSynthesisPlanSupport.SynthesisPlan,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void,
        makeAudioData: (String) async throws -> Data
    ) async throws {
        for chunk in plan.chunks {
            try Task.checkCancellation()
            let clipData = try await makeAudioData(chunk)
            let clip = await TextToSpeechQueuedClipFactory.clip(fromAudioData: clipData)
            try await onEvent(.clip(clip))
        }
    }

    private static func streamChunks(
        plan: TextToSpeechSynthesisPlanSupport.SynthesisPlan,
        streaming: SpeechStreamingCapability,
        onEvent: @escaping @MainActor (TextToSpeechSynthesisEvent) throws -> Void,
        makeStream: (String) async throws -> AsyncThrowingStream<Data, Error>
    ) async throws {
        try Task.checkCancellation()
        try await onEvent(.streamStarted(sampleRate: streaming.sampleRate))

        // Successive text chunks share one PCM format, so their audio concatenates seamlessly.
        for chunk in plan.chunks {
            try Task.checkCancellation()
            for try await audio in try await makeStream(chunk) {
                try Task.checkCancellation()
                guard !audio.isEmpty else { continue }
                try await onEvent(.streamedPCM(audio))
            }
        }
    }
}
