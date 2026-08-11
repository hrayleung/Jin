import Foundation

enum MiMoModelIDs {
    static let v25Pro = "mimo-v2.5-pro"
    static let v25 = "mimo-v2.5"
    static let v2Pro = "mimo-v2-pro"
    static let v2Omni = "mimo-v2-omni"
    static let v2Flash = "mimo-v2-flash"

    static let tokenPlanExactModelIDs: Set<String> = [
        v25Pro,
        v25,
        v2Pro,
        v2Omni,
        v2Flash,
    ]

    static let ttsV25 = "mimo-v2.5-tts"
    static let ttsV25VoiceDesign = "mimo-v2.5-tts-voicedesign"
    static let ttsV25VoiceClone = "mimo-v2.5-tts-voiceclone"

    /// Retired 2026-06-30 along with the rest of the MiMo V2 series. Kept only so
    /// stored preferences can be recognised and migrated to `ttsV25`.
    static let retiredTTSV2 = "mimo-v2-tts"

    static let textToSpeechModelIDs: Set<String> = [
        ttsV25,
        ttsV25VoiceDesign,
        ttsV25VoiceClone,
    ]

    /// The V2.5 series only accepts these two container formats.
    static let textToSpeechResponseFormats: [String] = [
        "wav",
        "pcm16",
    ]

    static let textToSpeechResponseFormatSet = Set(textToSpeechResponseFormats)

    /// Every speech-synthesis model the platform has served, retired ones included. Used to
    /// keep them out of the chat model catalog, where they were never usable.
    static let allTextToSpeechModelIDs: Set<String> = textToSpeechModelIDs.union([retiredTTSV2])

    static func isTextToSpeechModelID(_ modelID: String) -> Bool {
        textToSpeechModelIDs.contains(modelID.trimmedLowercased)
    }

    static func isAnyTextToSpeechModelID(_ modelID: String) -> Bool {
        allTextToSpeechModelIDs.contains(modelID.trimmedLowercased)
    }
}
