import Foundation
import TTSKit

extension TTSKitService {
    nonisolated static var placeholderLibrarySnapshot: LibrarySnapshot {
        LibrarySnapshot(
            repositoryRootURL: defaultRepositoryURL(),
            localModels: [],
            loadedModelID: nil,
            recommendedModelID: recommendedModelVariantStatic()
        )
    }

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

    nonisolated static func recommendedModelVariantStatic() -> String {
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
