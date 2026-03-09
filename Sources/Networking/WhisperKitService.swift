import Foundation
import WhisperKit

actor WhisperKitService {
    static let shared = WhisperKitService()

    struct LocalModel: Identifiable, Sendable, Equatable {
        let id: String
        let folderURL: URL
        let presetID: String?

        var folderPath: String { folderURL.path }
    }

    struct LibrarySnapshot: Sendable, Equatable {
        let repositoryRootURL: URL
        let localModels: [LocalModel]
        let loadedModelID: String?
        let recommendedModelID: String

        func localModel(id: String) -> LocalModel? {
            localModels.first { $0.id == id }
        }

        func localModel(matching selection: String) -> LocalModel? {
            if let exactMatch = localModel(id: selection) {
                return exactMatch
            }

            guard let preset = WhisperKitModelCatalog.preset(for: selection) else {
                return nil
            }

            if preset.matchesExactModelID(recommendedModelID),
               let recommendedMatch = localModel(id: recommendedModelID) {
                return recommendedMatch
            }

            return localModels.first { preset.matchesExactModelID($0.id) }
        }

        func loadedModelMatches(selection: String) -> Bool {
            guard let loadedModelID else { return false }
            if loadedModelID == selection { return true }
            guard let preset = WhisperKitModelCatalog.preset(for: selection) else { return false }
            return preset.matchesExactModelID(loadedModelID)
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
    private var whisperKit: WhisperKit?
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
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    nonisolated func recommendedModelVariant() -> String {
        Self.recommendedModelVariantStatic()
    }

    nonisolated private static func recommendedModelVariantStatic() -> String {
        WhisperKit.recommendedModels().default
    }

    nonisolated static func discoverLocalModels(in rootURL: URL) -> [LocalModel] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let models = children.compactMap { childURL -> LocalModel? in
            guard isValidModelFolder(childURL) else { return nil }
            return LocalModel(
                id: childURL.lastPathComponent,
                folderURL: childURL,
                presetID: WhisperKitModelCatalog.preset(for: childURL.lastPathComponent)?.id
            )
        }

        return sortLocalModels(models)
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
        let currentSnapshot = refreshLocalModels()

        if whisperKit != nil,
           currentSnapshot.loadedModelMatches(selection: selection),
           let loadedModelID,
           let loadedModel = currentSnapshot.localModel(id: loadedModelID),
           case .ready = status {
            return loadedModel
        }

        whisperKit = nil
        loadedModelID = nil

        do {
            let resolvedModel: LocalModel

            if let localModel = currentSnapshot.localModel(matching: selection) {
                status = .loading
                resolvedModel = localModel
            } else {
                status = .downloading(progress: 0)
                let downloadQuery = WhisperKitModelCatalog.preferredDownloadQuery(
                    for: selection,
                    recommendedModelID: currentSnapshot.recommendedModelID
                )
                let downloadedFolder = try await WhisperKit.download(
                    variant: downloadQuery,
                    progressCallback: { [weak self] progress in
                        guard let self else { return }
                        Task {
                            await self.updateDownloadProgress(progress.fractionCompleted)
                        }
                    }
                )

                let refreshedSnapshot = refreshLocalModels()
                if let exactMatch = refreshedSnapshot.localModel(id: downloadedFolder.lastPathComponent) {
                    resolvedModel = exactMatch
                } else if let selectedMatch = refreshedSnapshot.localModel(matching: selection) {
                    resolvedModel = selectedMatch
                } else {
                    let fallbackModel = LocalModel(
                        id: downloadedFolder.lastPathComponent,
                        folderURL: downloadedFolder,
                        presetID: WhisperKitModelCatalog.preset(for: selection)?.id
                    )
                    localModels = Self.sortLocalModels(localModels + [fallbackModel])
                    resolvedModel = fallbackModel
                }
                status = .loading
            }

            let config = WhisperKitConfig(
                modelFolder: resolvedModel.folderPath,
                verbose: false,
                load: true,
                download: false
            )
            let pipe = try await WhisperKit(config)
            whisperKit = pipe
            loadedModelID = resolvedModel.id
            status = .ready(modelID: resolvedModel.id)
            return resolvedModel
        } catch {
            whisperKit = nil
            loadedModelID = nil
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func unloadModel() {
        cancelIdleUnload()
        let previousModelID = loadedModelID
        whisperKit = nil
        loadedModelID = nil
        if let previousModelID {
            status = .unloaded(modelID: previousModelID)
        } else {
            status = .idle
        }
    }

    func deleteModel(_ modelID: String) throws {
        cancelIdleUnload()
        let snapshot = refreshLocalModels()
        guard let model = snapshot.localModel(id: modelID) else { return }

        if loadedModelID == modelID {
            whisperKit = nil
            loadedModelID = nil
        }

        try FileManager.default.removeItem(at: model.folderURL)
        localModels = Self.discoverLocalModels(in: modelsRepositoryURL)
        if let loadedModelID {
            status = .ready(modelID: loadedModelID)
        } else {
            status = .idle
        }
    }

    // MARK: - Transcription

    func transcribe(audioPath: String, language: String?, translateToEnglish: Bool) async throws -> String {
        cancelIdleUnload()
        defer { scheduleIdleUnload() }

        guard let pipe = whisperKit else {
            throw SpeechExtensionError.whisperKitModelNotLoaded
        }

        let task: DecodingTask = translateToEnglish ? .translate : .transcribe
        let lang = language
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let options = DecodingOptions(
            task: task,
            language: lang,
            temperature: 0.0,
            skipSpecialTokens: true
        )

        let results = try await pipe.transcribe(
            audioPath: audioPath,
            decodeOptions: options
        )

        let text = results.map(\.text).joined(separator: " ")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SpeechExtensionError.whisperKitTranscriptionFailed("No speech detected in recording.")
        }

        return text
    }

    // MARK: - Private

    private func updateDownloadProgress(_ fraction: Double) {
        status = .downloading(progress: fraction)
    }

    private nonisolated static func isValidModelFolder(_ folderURL: URL) -> Bool {
        guard ((try? folderURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) else {
            return false
        }

        return hasModelArtifact(named: "MelSpectrogram", in: folderURL)
            && hasModelArtifact(named: "AudioEncoder", in: folderURL)
            && hasModelArtifact(named: "TextDecoder", in: folderURL)
    }

    private nonisolated static func hasModelArtifact(named name: String, in folderURL: URL) -> Bool {
        let fileManager = FileManager.default
        return ["mlmodelc", "mlpackage"].contains { ext in
            fileManager.fileExists(atPath: folderURL.appendingPathComponent("\(name).\(ext)").path)
        }
    }

    private nonisolated static func sortLocalModels(_ models: [LocalModel]) -> [LocalModel] {
        let presetOrder = Dictionary(uniqueKeysWithValues: WhisperKitModelCatalog.presets.enumerated().map { ($1.id, $0) })

        return models.sorted { lhs, rhs in
            let lhsOrder = lhs.presetID.flatMap { presetOrder[$0] } ?? Int.max
            let rhsOrder = rhs.presetID.flatMap { presetOrder[$0] } ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }
}
