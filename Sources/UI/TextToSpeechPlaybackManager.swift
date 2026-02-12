import Foundation
import AVFoundation

@MainActor
final class TextToSpeechPlaybackManager: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case generating(messageID: UUID)
        case playing(messageID: UUID)
        case paused(messageID: UUID)
    }

    struct OpenAIConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
        let responseFormat: String
        let speed: Double?
        let instructions: String?
    }

    struct GroqConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let voice: String
        let responseFormat: String
    }

    struct ElevenLabsConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let voiceId: String
        let modelId: String?
        let outputFormat: String?
        let optimizeStreamingLatency: Int?
        let enableLogging: Bool?
        let voiceSettings: ElevenLabsTTSClient.VoiceSettings?
    }

    enum SynthesisConfig: Sendable {
        case openai(OpenAIConfig)
        case groq(GroqConfig)
        case elevenlabs(ElevenLabsConfig)
    }

    @Published private(set) var state: State = .idle

    private var synthesisTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var queue: [Data] = []
    private var currentMessageID: UUID?
    private var currentErrorHandler: ((Error) -> Void)?
    private var didFinishSynthesis = true

    func toggleSpeak(
        messageID: UUID,
        text: String,
        config: SynthesisConfig,
        onError: @escaping (Error) -> Void
    ) {
        if case .playing(let id) = state, id == messageID {
            pause(messageID: messageID)
            return
        }
        if case .paused(let id) = state, id == messageID {
            resume(messageID: messageID)
            return
        }
        if case .generating(let id) = state, id == messageID {
            stop(messageID: messageID)
            return
        }

        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        queue = []
        didFinishSynthesis = false
        currentMessageID = messageID
        currentErrorHandler = onError
        state = .generating(messageID: messageID)

        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.synthesizeAndEnqueueAudioClips(text: trimmed, config: config, messageID: messageID)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.completeSynthesisIfCurrent(messageID: messageID)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.failSynthesisIfCurrent(messageID: messageID, error: error)
                }
            }
        }
    }

    func isGenerating(messageID: UUID) -> Bool {
        state == .generating(messageID: messageID)
    }

    func isPlaying(messageID: UUID) -> Bool {
        state == .playing(messageID: messageID)
    }

    func isPaused(messageID: UUID) -> Bool {
        state == .paused(messageID: messageID)
    }

    func isActive(messageID: UUID) -> Bool {
        switch state {
        case .generating(let id), .playing(let id), .paused(let id):
            return id == messageID
        case .idle:
            return false
        }
    }

    func pause(messageID: UUID) {
        guard case .playing(let id) = state, id == messageID else { return }

        if let player, player.isPlaying {
            player.pause()
        }

        state = .paused(messageID: messageID)
    }

    func resume(messageID: UUID) {
        guard case .paused(let id) = state, id == messageID else { return }

        state = .playing(messageID: messageID)

        if let player, !player.isPlaying {
            player.play()
        }

        playNextClipIfNeeded()
    }

    func stop(messageID: UUID) {
        guard isActive(messageID: messageID) else { return }
        stop()
    }

    func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil

        player?.stop()
        player = nil
        queue = []
        currentMessageID = nil
        currentErrorHandler = nil
        didFinishSynthesis = true
        state = .idle
    }

    private func synthesizeAndEnqueueAudioClips(
        text: String,
        config: SynthesisConfig,
        messageID: UUID
    ) async throws {
        switch config {
        case .openai(let openAI):
            let format = openAI.responseFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard Self.supportedOpenAIPlaybackFormats.contains(format) else {
                throw LLMError.invalidRequest(message: "OpenAI format “\(format)” is not playable in Jin. Choose mp3, wav, aac, flac, or pcm.")
            }

            let chunks = TextChunker.chunks(for: text, maxCharacters: 4096)
            let client = OpenAIAudioClient(apiKey: openAI.apiKey, baseURL: openAI.baseURL)

            for chunk in chunks {
                try Task.checkCancellation()
                let clip = try await client.createSpeech(
                    input: chunk,
                    model: openAI.model,
                    voice: openAI.voice,
                    responseFormat: format,
                    speed: openAI.speed,
                    instructions: openAI.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : openAI.instructions,
                    streamFormat: nil
                )
                enqueueClipIfCurrent(
                    wrappingOpenAIPCMIfNeeded(clip, responseFormat: format),
                    messageID: messageID
                )
            }

        case .groq(let groq):
            let chunks = TextChunker.chunks(for: text, maxCharacters: 200)
            let client = GroqAudioClient(apiKey: groq.apiKey, baseURL: groq.baseURL)

            for chunk in chunks {
                try Task.checkCancellation()
                let clip = try await client.createSpeech(
                    input: chunk,
                    model: groq.model,
                    voice: groq.voice,
                    responseFormat: groq.responseFormat
                )
                enqueueClipIfCurrent(clip, messageID: messageID)
            }

        case .elevenlabs(let eleven):
            let chunks = TextChunker.chunks(for: text, maxCharacters: 6000)
            let client = ElevenLabsTTSClient(apiKey: eleven.apiKey, baseURL: eleven.baseURL)

            for chunk in chunks {
                try Task.checkCancellation()
                let clip = try await client.createSpeech(
                    text: chunk,
                    voiceId: eleven.voiceId,
                    modelId: eleven.modelId,
                    outputFormat: eleven.outputFormat,
                    optimizeStreamingLatency: eleven.optimizeStreamingLatency,
                    enableLogging: eleven.enableLogging,
                    voiceSettings: eleven.voiceSettings
                )
                enqueueClipIfCurrent(
                    wrappingElevenLabsPCMIfNeeded(clip, outputFormat: eleven.outputFormat),
                    messageID: messageID
                )
            }
        }
    }

    private func enqueueClipIfCurrent(_ clip: Data, messageID: UUID) {
        guard currentMessageID == messageID else { return }

        queue.append(clip)

        if case .generating(let id) = state, id == messageID {
            state = .playing(messageID: messageID)
        }

        if case .playing(let id) = state, id == messageID {
            playNextClipIfNeeded()
        }
    }

    private func completeSynthesisIfCurrent(messageID: UUID) {
        guard currentMessageID == messageID else { return }

        synthesisTask = nil
        didFinishSynthesis = true

        if case .generating(let id) = state, id == messageID {
            state = .playing(messageID: messageID)
        }

        if case .playing(let id) = state, id == messageID {
            playNextClipIfNeeded()
        }
    }

    private func failSynthesisIfCurrent(messageID: UUID, error: Error) {
        guard currentMessageID == messageID else { return }

        currentErrorHandler?(error)
        stop()
    }

    private func finishPlaybackSession() {
        synthesisTask = nil
        player = nil
        queue = []
        currentMessageID = nil
        currentErrorHandler = nil
        didFinishSynthesis = true
        state = .idle
    }

    private func playNextClipIfNeeded() {
        guard case .playing = state else { return }
        guard let messageID = currentMessageID else {
            stop()
            return
        }

        if player != nil {
            return
        }

        guard !queue.isEmpty else {
            if didFinishSynthesis {
                finishPlaybackSession()
            }
            return
        }

        let clip = queue.removeFirst()
        do {
            let audioPlayer = try AVAudioPlayer(data: clip)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            player = audioPlayer
            state = .playing(messageID: messageID)
            audioPlayer.play()
        } catch {
            currentErrorHandler?(error)
            stop()
        }
    }

    private func wrappingElevenLabsPCMIfNeeded(_ data: Data, outputFormat: String?) -> Data {
        let format = (outputFormat ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard format.hasPrefix("pcm_") else { return data }

        let sampleRateString = format.replacingOccurrences(of: "pcm_", with: "")
        guard let sampleRate = Int(sampleRateString), sampleRate > 0 else { return data }

        // ElevenLabs `pcm_*` formats return raw 16-bit little-endian PCM. Wrap in a WAV container
        // so AVFoundation can decode it.
        return WAVContainer.wrapPCM16LEMono(pcmData: data, sampleRate: sampleRate)
    }

    private func wrappingOpenAIPCMIfNeeded(_ data: Data, responseFormat: String) -> Data {
        let format = responseFormat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard format == "pcm" else { return data }

        // OpenAI `pcm` response format returns raw 16-bit signed little-endian PCM at 24kHz without a header.
        // Wrap it in a WAV container for playback via AVFoundation.
        return WAVContainer.wrapPCM16LEMono(pcmData: data, sampleRate: 24_000)
    }

    private static let supportedOpenAIPlaybackFormats: Set<String> = [
        "mp3",
        "wav",
        "aac",
        "flac",
        "pcm"
    ]
}

private enum WAVContainer {
    static func wrapPCM16LEMono(pcmData: Data, sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let subchunk2Size = UInt32(pcmData.count)
        let chunkSize = UInt32(36) + subchunk2Size

        var header = Data()
        header.reserveCapacity(44)

        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.appendUInt32LE(chunkSize)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.appendUInt32LE(16) // Subchunk1Size (PCM)
        header.appendUInt16LE(1) // AudioFormat (PCM)
        header.appendUInt16LE(numChannels)
        header.appendUInt32LE(UInt32(sampleRate))
        header.appendUInt32LE(byteRate)
        header.appendUInt16LE(blockAlign)
        header.appendUInt16LE(bitsPerSample)

        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.appendUInt32LE(subchunk2Size)

        var out = Data()
        out.reserveCapacity(header.count + pcmData.count)
        out.append(header)
        out.append(pcmData)
        return out
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

extension TextToSpeechPlaybackManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.player === player {
                self.player = nil
            }
            playNextClipIfNeeded()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.player === player {
                self.player = nil
            }
            let err = error ?? LLMError.providerError(code: "audio_decode_error", message: "Failed to decode audio.")
            currentErrorHandler?(err)
            stop()
        }
    }
}

private enum TextChunker {
    static func chunks(for text: String, maxCharacters: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > maxCharacters else { return [trimmed] }

        var result: [String] = []
        result.reserveCapacity(max(2, trimmed.count / maxCharacters))

        let paragraphs = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        var current = ""

        func flush() {
            let out = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty {
                result.append(out)
            }
            current = ""
        }

        for paragraph in paragraphs {
            if paragraph.count > maxCharacters {
                flush()
                result.append(contentsOf: hardSplit(paragraph, maxCharacters: maxCharacters))
                continue
            }

            if current.isEmpty {
                current = paragraph
                continue
            }

            let candidate = current + "\n" + paragraph
            if candidate.count <= maxCharacters {
                current = candidate
            } else {
                flush()
                current = paragraph
            }
        }

        flush()
        return result
    }

    private static func hardSplit(_ text: String, maxCharacters: Int) -> [String] {
        guard maxCharacters > 0 else { return [text] }
        var out: [String] = []
        out.reserveCapacity(max(1, text.count / maxCharacters))

        var buffer = ""
        buffer.reserveCapacity(maxCharacters)

        for ch in text {
            buffer.append(ch)
            if buffer.count >= maxCharacters {
                out.append(buffer)
                buffer = ""
            }
        }

        if !buffer.isEmpty {
            out.append(buffer)
        }

        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
