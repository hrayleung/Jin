import Foundation
import TTSKit

struct TTSKitModelCatalog {
    struct Preset: Identifiable, Equatable, Sendable {
        let id: String
        let variant: TTSModelVariant
        let title: String
        let approximateSize: String
        let summary: String
        let supportsStyleInstruction: Bool
        let versionDirectory: String
    }

    struct VoiceOption: Identifiable, Equatable, Sendable {
        let id: String
        let displayName: String
        let summary: String
    }

    struct LanguageOption: Identifiable, Equatable, Sendable {
        let id: String
        let displayName: String
    }

    static let defaultModelID = TTSModelVariant.defaultForCurrentPlatform.rawValue

    static let presets: [Preset] = TTSModelVariant.allCases
        .filter(\.isAvailableOnCurrentPlatform)
        .map { variant in
            let approximateSize: String
            let summary: String

            switch variant {
            case .qwen3TTS_0_6b:
                approximateSize = "~1 GB"
                summary = "Fastest startup and the best default for everyday playback."
            case .qwen3TTS_1_7b:
                approximateSize = "~2.2 GB"
                summary = "Higher quality and supports style directions, but takes longer to load and generate."
            }

            return Preset(
                id: variant.rawValue,
                variant: variant,
                title: variant.displayName,
                approximateSize: approximateSize,
                summary: summary,
                supportsStyleInstruction: variant.supportsVoiceDirection,
                versionDirectory: variant.versionDir
            )
        }

    static let voices: [VoiceOption] = Qwen3Speaker.allCases.map { voice in
        VoiceOption(
            id: voice.rawValue,
            displayName: voice.displayName,
            summary: "\(voice.nativeLanguage) · \(voice.voiceDescription)"
        )
    }

    static let languages: [LanguageOption] = Qwen3Language.allCases.map { language in
        LanguageOption(
            id: language.rawValue,
            displayName: language.rawValue.capitalized
        )
    }

    static func preset(for modelID: String) -> Preset? {
        let normalizedID = normalizedModelID(modelID)
        return presets.first { $0.id == normalizedID }
    }

    static func normalizedModelID(_ rawModelID: String?) -> String {
        let trimmed = (rawModelID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultModelID }

        if TTSModelVariant(rawValue: trimmed) != nil {
            return trimmed
        }

        switch canonicalModelID(trimmed) {
        case "0.6b", "qwen3tts0.6b", "qwen3-tts-0.6b":
            return TTSModelVariant.qwen3TTS_0_6b.rawValue
        case "1.7b", "qwen3tts1.7b", "qwen3-tts-1.7b":
            return TTSModelVariant.qwen3TTS_1_7b.rawValue
        default:
            return defaultModelID
        }
    }

    private static func canonicalModelID(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}

enum TTSKitPlaybackMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case stream
    case generateFirst = "generate_first"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto Streaming"
        case .stream:
            return "Immediate Streaming"
        case .generateFirst:
            return "Generate First"
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return "Recommended. TTSKit measures the first generation step and buffers just enough audio to reduce stutter."
        case .stream:
            return "Starts as soon as the first frame is ready. Lowest latency, but can sound choppy on slower Macs."
        case .generateFirst:
            return "Waits for the whole clip before playback. Smoothest output, highest latency."
        }
    }

    var playbackStrategy: PlaybackStrategy {
        switch self {
        case .auto:
            return .auto
        case .stream:
            return .stream
        case .generateFirst:
            return .generateFirst
        }
    }

    static func resolved(_ rawValue: String?) -> TTSKitPlaybackMode {
        guard let rawValue else { return .auto }
        return TTSKitPlaybackMode(rawValue: rawValue) ?? .auto
    }
}