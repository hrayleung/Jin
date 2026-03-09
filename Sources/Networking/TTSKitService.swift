import Foundation
import TTSKit

actor TTSKitService {
    static let shared = TTSKitService()

    struct LocalModel: Identifiable, Sendable, Equatable {
        let id: String
        let repositoryRootURL: URL
        let versionDirectory: String
        let componentDirectories: [URL]

        var storagePathPattern: String {
            repositoryRootURL
                .appendingPathComponent("qwen3_tts", isDirectory: true)
                .appendingPathComponent("<component>", isDirectory: true)
                .appendingPathComponent(versionDirectory, isDirectory: true)
                .path
        }
    }

    struct LibrarySnapshot: Sendable, Equatable {
        let repositoryRootURL: URL
        let localModels: [LocalModel]
        let loadedModelID: String?
        let recommendedModelID: String

        func localModel(id: String) -> LocalModel? {
            localModels.first { $0.id == id }
        }

        func loadedModelMatches(selection: String) -> Bool {
            loadedModelID == TTSKitModelCatalog.normalizedModelID(selection)
        }
    }

    enum Status: Sendable, Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready(modelID: String)
        case unloaded(modelID: String)
        case error(String)
    }

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

    nonisolated static var placeholderLibrarySnapshot: LibrarySnapshot {
        LibrarySnapshot(
            repositoryRootURL: defaultRepositoryURL(),
            localModels: [],
            loadedModelID: nil,
            recommendedModelID: recommendedModelVariantStatic()
        )
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

    // MARK: - Repository

    nonisolated static func defaultRepositoryURL(documentsDirectory: URL? = nil) -> URL {
        let documents = documentsDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("ttskit-coreml", isDirectory: true)
    }

    nonisolated func recommendedModelVariant() -> String {
        Self.recommendedModelVariantStatic()
    }

    nonisolated private static func recommendedModelVariantStatic() -> String {
        TTSKit.recommendedModels().rawValue
    }

    nonisolated static func discoverLocalModels(in rootURL: URL) -> [LocalModel] {
        sortLocalModels(
            TTSKitModelCatalog.presets.compactMap { preset in
                let config = TTSKitConfig(
                    model: preset.variant,
                    modelFolder: rootURL,
                    download: false,
                    load: false
                )
                let requiredComponents: [(String, String)] = [
                    ("text_projector", config.textProjectorVariant),
                    ("code_embedder", config.codeEmbedderVariant),
                    ("multi_code_embedder", config.multiCodeEmbedderVariant),
                    ("code_decoder", config.codeDecoderVariant),
                    ("multi_code_decoder", config.multiCodeDecoderVariant),
                    ("speech_decoder", config.speechDecoderVariant)
                ]

                let isInstalled = requiredComponents.allSatisfy { component, variant in
                    config.modelURL(component: component, variant: variant) != nil
                }
                guard isInstalled else { return nil }

                return LocalModel(
                    id: preset.id,
                    repositoryRootURL: rootURL,
                    versionDirectory: preset.versionDirectory,
                    componentDirectories: config.componentDirectories(in: rootURL)
                )
            }
        )
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
                        onFirstAudioFrame?()
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

    func stopPlayback() async {
        guard let pipe = ttsKit else { return }
        await pipe.audioOutput.stopPlayback(waitForCompletion: false)
    }

    // MARK: - Private

    private func updateDownloadProgress(_ fraction: Double) {
        status = .downloading(progress: fraction)
    }

    private nonisolated static func normalizedOptionalString(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private nonisolated static func sortLocalModels(_ models: [LocalModel]) -> [LocalModel] {
        let order = Dictionary(uniqueKeysWithValues: TTSKitModelCatalog.presets.enumerated().map { ($1.id, $0) })
        return models.sorted { lhs, rhs in
            let lhsIndex = order[lhs.id] ?? Int.max
            let rhsIndex = order[rhs.id] ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
