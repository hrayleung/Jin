import Foundation
import AVFoundation

@MainActor
final class SpeechToTextManager: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case transcribing
    }

    struct OpenAIConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let translateToEnglish: Bool
        let language: String?
        let prompt: String?
        let responseFormat: String?
        let temperature: Double?
        let timestampGranularities: [String]?
    }

    struct GroqConfig: Sendable {
        let apiKey: String
        let baseURL: URL
        let model: String
        let translateToEnglish: Bool
        let language: String?
        let prompt: String?
        let responseFormat: String?
        let temperature: Double?
        let timestampGranularities: [String]?
    }

    enum TranscriptionConfig: Sendable {
        case openai(OpenAIConfig)
        case groq(GroqConfig)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var elapsedTimer: Timer?
    private var recordingURL: URL?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isTranscribing: Bool {
        state == .transcribing
    }

    func startRecording() async throws {
        guard state == .idle else { return }
        try await requestMicrophoneAccessIfNeeded()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin_recording_\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true

        self.recorder = recorder
        recordingURL = url
        elapsedSeconds = 0
        state = .recording(startedAt: Date())

        if !recorder.record() {
            cancelAndCleanup()
            throw SpeechExtensionError.speechRecordingFailed
        }

        startElapsedTimer()
    }

    func stopAndTranscribe(config: TranscriptionConfig) async throws -> String {
        guard case .recording = state else { return "" }
        guard let recorder, let recordingURL else { return "" }

        state = .transcribing
        stopElapsedTimer()

        recorder.stop()
        self.recorder = nil

        let fileData: Data
        do {
            fileData = try Data(contentsOf: recordingURL)
        } catch {
            cancelAndCleanup()
            throw SpeechExtensionError.speechRecordingFailed
        }

        do {
            let text = try await transcribe(data: fileData, config: config)
            cleanupRecordingFile()
            state = .idle
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            cleanupRecordingFile()
            state = .idle
            throw error
        }
    }

    func cancelAndCleanup() {
        stopElapsedTimer()
        recorder?.stop()
        recorder = nil
        cleanupRecordingFile()
        state = .idle
    }

    // MARK: - Private

    private func transcribe(data: Data, config: TranscriptionConfig) async throws -> String {
        switch config {
        case .openai(let openAI):
            let client = OpenAIAudioClient(apiKey: openAI.apiKey, baseURL: openAI.baseURL)
            if openAI.translateToEnglish {
                return try await client.createTranslation(
                    fileData: data,
                    filename: "recording.wav",
                    mimeType: "audio/wav",
                    model: openAI.model,
                    prompt: openAI.prompt,
                    responseFormat: openAI.responseFormat,
                    temperature: openAI.temperature
                )
            }

            return try await client.createTranscription(
                fileData: data,
                filename: "recording.wav",
                mimeType: "audio/wav",
                model: openAI.model,
                language: openAI.language,
                prompt: openAI.prompt,
                responseFormat: openAI.responseFormat,
                temperature: openAI.temperature,
                timestampGranularities: openAI.timestampGranularities
            )

        case .groq(let groq):
            let client = GroqAudioClient(apiKey: groq.apiKey, baseURL: groq.baseURL)
            if groq.translateToEnglish {
                return try await client.createTranslation(
                    fileData: data,
                    filename: "recording.wav",
                    mimeType: "audio/wav",
                    model: groq.model,
                    prompt: groq.prompt,
                    responseFormat: groq.responseFormat,
                    temperature: groq.temperature
                )
            }

            return try await client.createTranscription(
                fileData: data,
                filename: "recording.wav",
                mimeType: "audio/wav",
                model: groq.model,
                language: groq.language,
                prompt: groq.prompt,
                responseFormat: groq.responseFormat,
                temperature: groq.temperature,
                timestampGranularities: groq.timestampGranularities
            )
        }
    }

    private func requestMicrophoneAccessIfNeeded() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            if !granted {
                throw SpeechExtensionError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw SpeechExtensionError.microphonePermissionDenied
        @unknown default:
            throw SpeechExtensionError.microphonePermissionDenied
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard case .recording(let startedAt) = self.state else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func cleanupRecordingFile() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }
}

extension SpeechToTextManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor in
            cancelAndCleanup()
        }
    }
}
