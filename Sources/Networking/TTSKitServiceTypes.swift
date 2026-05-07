import Foundation

extension TTSKitService {
    struct GeneratedSpeechChunk: Sendable {
        let samples: [Float]
        let sampleRate: Int
    }

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
}
