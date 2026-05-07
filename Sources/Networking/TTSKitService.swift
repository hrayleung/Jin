import Foundation
import TTSKit

actor TTSKitService {
    static let shared = TTSKitService()

    private static let idleUnloadDelay: Duration = .seconds(120)

    private let modelsRepositoryURL: URL
    private var ttsKit: TTSKit?
    private var loadedModelID: String?
    private var localModels: [LocalModel]
    private var statusContinuation: AsyncStream<Status>.Continuation?
    private var idleUnloadTask: Task<Void, Never>?

    private(set) var status: Status = .idle {
        didSet {
            statusContinuation?.yield(status)
        }
    }

    private init() {
        let modelsRepositoryURL = Self.defaultRepositoryURL()
        self.modelsRepositoryURL = modelsRepositoryURL
        self.localModels = Self.discoverLocalModels(in: modelsRepositoryURL)
    }

    // MARK: - Status Stream

    func statusStream() -> AsyncStream<Status> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
            continuation.yield(self.status)
            continuation.onTermination = { @Sendable _ in
                Task { await self.clearContinuation() }
            }
        }
    }

    private func clearContinuation() {
        statusContinuation = nil
    }

    // MARK: - Library Snapshot

    func librarySnapshot() -> LibrarySnapshot {
        refreshLocalModels()
    }

    @discardableResult
    func refreshLocalModels() -> LibrarySnapshot {
        localModels = Self.discoverLocalModels(in: modelsRepositoryURL)
        return LibrarySnapshot(
            repositoryRootURL: modelsRepositoryURL,
            localModels: localModels,
            loadedModelID: loadedModelID,
            recommendedModelID: Self.recommendedModelVariantStatic()
        )
    }

    // MARK: - Model Lifecycle

    // MARK: - Idle Auto-Unload

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task {
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled else { return }
            unloadModel()
        }
    }

    private func cancelIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    @discardableResult
    func loadModel(_ selection: String) async throws -> LocalModel {
        cancelIdleUnload()
        let modelID = TTSKitModelCatalog.normalizedModelID(selection)
        guard let preset = TTSKitModelCatalog.preset(for: modelID) else {
            throw SpeechExtensionError.ttsKitGenerationFailed("Unknown TTSKit model: \(selection)")
        }

        let currentSnapshot = refreshLocalModels()
        if ttsKit != nil,
           currentSnapshot.loadedModelMatches(selection: modelID),
           let loadedModel = currentSnapshot.localModel(id: modelID),
           case .ready = status {
            return loadedModel
        }

        ttsKit = nil
        loadedModelID = nil

        do {
            if currentSnapshot.localModel(id: modelID) == nil {
                status = .downloading(progress: 0)
                _ = try await TTSKit.download(
                    variant: preset.variant,
                    progressCallback: { [weak self] progress in
                        guard let self else { return }
                        Task {
                            await self.updateDownloadProgress(progress.fractionCompleted)
                        }
                    }
                )
            }

            status = .loading

            let config = TTSKitConfig(
                model: preset.variant,
                modelFolder: modelsRepositoryURL,
                download: false,
                load: true
            )
            let pipe = try await TTSKit(config)
            ttsKit = pipe
            loadedModelID = modelID
            let refreshedSnapshot = refreshLocalModels()
            status = .ready(modelID: modelID)
            return refreshedSnapshot.localModel(id: modelID)
                ?? LocalModel(
                    id: modelID,
                    repositoryRootURL: modelsRepositoryURL,
                    versionDirectory: preset.versionDirectory,
                    componentDirectories: []
                )
        } catch {
            ttsKit = nil
            loadedModelID = nil
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func unloadModel() {
        cancelIdleUnload()
        let previousModelID = loadedModelID
        ttsKit = nil
        loadedModelID = nil
        if let previousModelID {
            status = .unloaded(modelID: previousModelID)
        } else {
            status = .idle
        }
    }

    func deleteModel(_ selection: String) throws {
        cancelIdleUnload()
        let modelID = TTSKitModelCatalog.normalizedModelID(selection)
        let snapshot = refreshLocalModels()
        guard let localModel = snapshot.localModel(id: modelID) else { return }

        if loadedModelID == modelID {
            ttsKit = nil
            loadedModelID = nil
        }

        let fileManager = FileManager.default
        for directory in localModel.componentDirectories where fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }

        localModels = Self.discoverLocalModels(in: modelsRepositoryURL)
        if let loadedModelID {
            status = .ready(modelID: loadedModelID)
        } else {
            status = .idle
        }
    }

    // MARK: - Playback

    func playSpeech(
        text: String,
        voice: String?,
        language: String?,
        styleInstruction: String?,
        playbackMode: TTSKitPlaybackMode,
        onProgress: (@Sendable ([Float], Int) -> Void)? = nil,
        onFirstAudioFrame: (@Sendable () -> Void)? = nil
    ) async throws {
        cancelIdleUnload()
        defer { scheduleIdleUnload() }

        guard let pipe = ttsKit else {
            throw SpeechExtensionError.ttsKitModelNotLoaded
        }

        let resolvedVoice = Self.normalizedOptionalString(voice)
        let resolvedLanguage = Self.normalizedOptionalString(language)
        let resolvedInstruction = Self.normalizedOptionalString(styleInstruction)
        let sampleRate = pipe.sampleRate
        let firstAudioFrameGate = FirstAudioFrameGate()

        var options = GenerationOptions()
        options.instruction = resolvedInstruction

        try await withTaskCancellationHandler {
            _ = try await pipe.play(
                text: text,
                voice: resolvedVoice,
                language: resolvedLanguage,
                options: options,
                playbackStrategy: playbackMode.playbackStrategy,
                callback: { progress in
                    if !progress.audio.isEmpty {
                        firstAudioFrameGate.emitIfNeeded {
                            onFirstAudioFrame?()
                        }
                        onProgress?(progress.audio, sampleRate)
                    }
                    return true
                }
            )
        } onCancel: {
            Task {
                await pipe.audioOutput.stopPlayback(waitForCompletion: false)
            }
        }
    }

    func generateSpeech(
        text: String,
        voice: String?,
        language: String?,
        styleInstruction: String?,
        onProgress: (@Sendable (GeneratedSpeechChunk) async -> Void)? = nil
    ) async throws {
        cancelIdleUnload()
        defer { scheduleIdleUnload() }

        guard let pipe = ttsKit else {
            throw SpeechExtensionError.ttsKitModelNotLoaded
        }

        let resolvedVoice = Self.normalizedOptionalString(voice)
        let resolvedLanguage = Self.normalizedOptionalString(language)
        let resolvedInstruction = Self.normalizedOptionalString(styleInstruction)
        let sampleRate = pipe.sampleRate

        var options = GenerationOptions()
        options.instruction = resolvedInstruction

        let progressCallbacks = AsyncProgressCallbackQueue()

        do {
            _ = try await pipe.generate(
                text: text,
                voice: resolvedVoice,
                language: resolvedLanguage,
                options: options,
                callback: { progress in
                    if !progress.audio.isEmpty, let onProgress {
                        progressCallbacks.enqueue {
                            await onProgress(
                                GeneratedSpeechChunk(
                                    samples: progress.audio,
                                    sampleRate: sampleRate
                                )
                            )
                        }
                    }
                    return true
                }
            )
            await progressCallbacks.waitForCompletion()
        } catch {
            await progressCallbacks.waitForCompletion()
            throw error
        }
    }

    func stopPlayback() async {
        guard let pipe = ttsKit else { return }
        await pipe.audioOutput.stopPlayback(waitForCompletion: false)
    }

    func currentPlaybackTime() -> TimeInterval {
        guard let pipe = ttsKit else { return 0 }
        return pipe.audioOutput.currentPlaybackTime
    }

    // MARK: - Progress

    private func updateDownloadProgress(_ fraction: Double) {
        status = .downloading(progress: fraction)
    }
}
