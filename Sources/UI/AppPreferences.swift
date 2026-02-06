import Foundation

enum AppPreferenceKeys {
    static let newChatModelMode = "newChatModelMode"
    static let newChatFixedProviderID = "newChatFixedProviderID"
    static let newChatFixedModelID = "newChatFixedModelID"

    static let newChatMCPMode = "newChatMCPMode"
    static let newChatFixedMCPEnabled = "newChatFixedMCPEnabled"
    static let newChatFixedMCPUseAllServers = "newChatFixedMCPUseAllServers"
    static let newChatFixedMCPServerIDsJSON = "newChatFixedMCPServerIDsJSON"

    // MARK: - Extensions

    // Plugin visibility toggles (default: true)
    static let pluginTextToSpeechEnabled = "pluginTextToSpeechEnabled"
    static let pluginSpeechToTextEnabled = "pluginSpeechToTextEnabled"
    static let pluginMistralOCREnabled = "pluginMistralOCREnabled"
    static let pluginDeepSeekOCREnabled = "pluginDeepSeekOCREnabled"

    // Text to Speech
    static let ttsProvider = "ttsProvider"

    static let ttsOpenAIBaseURL = "ttsOpenAIBaseURL"
    static let ttsOpenAIModel = "ttsOpenAIModel"
    static let ttsOpenAIVoice = "ttsOpenAIVoice"
    static let ttsOpenAIResponseFormat = "ttsOpenAIResponseFormat"
    static let ttsOpenAISpeed = "ttsOpenAISpeed"
    static let ttsOpenAIInstructions = "ttsOpenAIInstructions"

    static let ttsGroqBaseURL = "ttsGroqBaseURL"
    static let ttsGroqModel = "ttsGroqModel"
    static let ttsGroqVoice = "ttsGroqVoice"
    static let ttsGroqResponseFormat = "ttsGroqResponseFormat"

    static let ttsElevenLabsBaseURL = "ttsElevenLabsBaseURL"
    static let ttsElevenLabsModelID = "ttsElevenLabsModelID"
    static let ttsElevenLabsVoiceID = "ttsElevenLabsVoiceID"
    static let ttsElevenLabsOutputFormat = "ttsElevenLabsOutputFormat"
    static let ttsElevenLabsOptimizeStreamingLatency = "ttsElevenLabsOptimizeStreamingLatency"
    static let ttsElevenLabsEnableLogging = "ttsElevenLabsEnableLogging"
    static let ttsElevenLabsStability = "ttsElevenLabsStability"
    static let ttsElevenLabsSimilarityBoost = "ttsElevenLabsSimilarityBoost"
    static let ttsElevenLabsStyle = "ttsElevenLabsStyle"
    static let ttsElevenLabsUseSpeakerBoost = "ttsElevenLabsUseSpeakerBoost"

    // Speech to Text
    static let sttProvider = "sttProvider"
    static let sttAddRecordingAsFile = "sttAddRecordingAsFile"

    static let sttOpenAIBaseURL = "sttOpenAIBaseURL"
    static let sttOpenAIModel = "sttOpenAIModel"
    static let sttOpenAILanguage = "sttOpenAILanguage"
    static let sttOpenAIPrompt = "sttOpenAIPrompt"
    static let sttOpenAITranslateToEnglish = "sttOpenAITranslateToEnglish"
    static let sttOpenAIResponseFormat = "sttOpenAIResponseFormat"
    static let sttOpenAITemperature = "sttOpenAITemperature"
    static let sttOpenAITimestampGranularitiesJSON = "sttOpenAITimestampGranularitiesJSON"

    static let sttGroqBaseURL = "sttGroqBaseURL"
    static let sttGroqModel = "sttGroqModel"
    static let sttGroqLanguage = "sttGroqLanguage"
    static let sttGroqPrompt = "sttGroqPrompt"
    static let sttGroqTranslateToEnglish = "sttGroqTranslateToEnglish"
    static let sttGroqResponseFormat = "sttGroqResponseFormat"
    static let sttGroqTemperature = "sttGroqTemperature"
    static let sttGroqTimestampGranularitiesJSON = "sttGroqTimestampGranularitiesJSON"
}

enum NewChatModelMode: String, CaseIterable, Identifiable {
    case fixed
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Use Specific Model"
        case .lastUsed: return "Use Last Used Model"
        }
    }
}

enum NewChatMCPMode: String, CaseIterable, Identifiable {
    case fixed
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: return "Use Custom Defaults"
        case .lastUsed: return "Use Last Chat's MCP"
        }
    }
}

enum AppPreferences {
    static func pluginEnabledPreferenceKey(for pluginID: String) -> String? {
        switch pluginID {
        case "text_to_speech":
            return AppPreferenceKeys.pluginTextToSpeechEnabled
        case "speech_to_text":
            return AppPreferenceKeys.pluginSpeechToTextEnabled
        case "mistral_ocr":
            return AppPreferenceKeys.pluginMistralOCREnabled
        case "deepseek_ocr":
            return AppPreferenceKeys.pluginDeepSeekOCREnabled
        default:
            return nil
        }
    }

    static func isPluginEnabled(_ pluginID: String, defaults: UserDefaults = .standard) -> Bool {
        guard let key = pluginEnabledPreferenceKey(for: pluginID) else { return true }
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        return true
    }

    static func setPluginEnabled(_ enabled: Bool, for pluginID: String, defaults: UserDefaults = .standard) {
        guard let key = pluginEnabledPreferenceKey(for: pluginID) else { return }
        defaults.set(enabled, forKey: key)
    }

    static func decodeStringArrayJSON(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func encodeStringArrayJSON(_ value: [String]) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
