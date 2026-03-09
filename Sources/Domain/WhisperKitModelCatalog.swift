import Foundation

enum WhisperKitModelCatalog {
    struct Preset: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let approximateSize: String
        let summary: String
        let downloadCandidates: [String]
        let exactModelIDs: [String]

        func matches(selection: String) -> Bool {
            id == selection || exactModelIDs.contains(selection)
        }

        func matchesExactModelID(_ modelID: String) -> Bool {
            exactModelIDs.contains(modelID)
        }
    }

    static let defaultSelection = "base"

    static let presets: [Preset] = [
        Preset(
            id: "tiny",
            title: "Tiny",
            approximateSize: "~40 MB",
            summary: "Smallest download. Good for quick tests, weakest accuracy.",
            downloadCandidates: [
                "openai_whisper-tiny",
                "openai_whisper-tiny.en"
            ],
            exactModelIDs: [
                "openai_whisper-tiny",
                "openai_whisper-tiny.en"
            ]
        ),
        Preset(
            id: "base",
            title: "Base",
            approximateSize: "~75 MB",
            summary: "Fast setup with solid everyday accuracy.",
            downloadCandidates: [
                "openai_whisper-base",
                "openai_whisper-base.en"
            ],
            exactModelIDs: [
                "openai_whisper-base",
                "openai_whisper-base.en"
            ]
        ),
        Preset(
            id: "small",
            title: "Small",
            approximateSize: "~250 MB",
            summary: "Better accuracy than Base with a moderate memory cost.",
            downloadCandidates: [
                "openai_whisper-small",
                "openai_whisper-small.en"
            ],
            exactModelIDs: [
                "openai_whisper-small",
                "openai_whisper-small.en"
            ]
        ),
        Preset(
            id: "distil-large-v3",
            title: "Distil Large v3",
            approximateSize: "~600 MB",
            summary: "Faster large-class model. Strong accuracy without the heaviest footprint.",
            downloadCandidates: [
                "distil-whisper_distil-large-v3_594MB",
                "distil-whisper_distil-large-v3",
                "distil-whisper_distil-large-v3_turbo_600MB",
                "distil-whisper_distil-large-v3_turbo"
            ],
            exactModelIDs: [
                "distil-whisper_distil-large-v3_594MB",
                "distil-whisper_distil-large-v3",
                "distil-whisper_distil-large-v3_turbo_600MB",
                "distil-whisper_distil-large-v3_turbo"
            ]
        ),
        Preset(
            id: "large-v3",
            title: "Large v3",
            approximateSize: "~600-950 MB",
            summary: "Best accuracy. Highest download size and memory use.",
            downloadCandidates: [
                "openai_whisper-large-v3-v20240930_626MB",
                "openai_whisper-large-v3-v20240930",
                "openai_whisper-large-v3_947MB",
                "openai_whisper-large-v3"
            ],
            exactModelIDs: [
                "openai_whisper-large-v3-v20240930_626MB",
                "openai_whisper-large-v3-v20240930",
                "openai_whisper-large-v3_947MB",
                "openai_whisper-large-v3"
            ]
        )
    ]

    static func preset(for selection: String) -> Preset? {
        presets.first { $0.matches(selection: selection) }
    }

    static func recommendedPreset(for recommendedModelID: String) -> Preset? {
        presets.first { $0.matchesExactModelID(recommendedModelID) }
    }

    static func preferredDownloadQuery(for selection: String, recommendedModelID: String?) -> String {
        guard let preset = preset(for: selection) else { return selection }
        if let recommendedModelID, preset.matchesExactModelID(recommendedModelID) {
            return recommendedModelID
        }
        return preset.downloadCandidates.first ?? selection
    }

    static func title(for selectionOrModelID: String) -> String {
        preset(for: selectionOrModelID)?.title ?? selectionOrModelID
    }
}
