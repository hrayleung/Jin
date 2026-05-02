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
    static let ttsV2 = "mimo-v2-tts"

    static let textToSpeechModelIDs: Set<String> = [
        ttsV25,
        ttsV25VoiceDesign,
        ttsV25VoiceClone,
        ttsV2,
    ]

    static let textToSpeechResponseFormats: [String] = [
        "wav",
        "mp3",
        "pcm",
        "pcm16",
    ]

    static let textToSpeechResponseFormatSet = Set(textToSpeechResponseFormats)

    static func isTextToSpeechModelID(_ modelID: String) -> Bool {
        textToSpeechModelIDs.contains(modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
