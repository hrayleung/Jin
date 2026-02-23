import Foundation

enum AppPreferenceKeys {

    // MARK: - New Chat Defaults

    static let newChatModelMode = "newChatModelMode"
    static let newChatFixedProviderID = "newChatFixedProviderID"
    static let newChatFixedModelID = "newChatFixedModelID"

    static let newChatMCPMode = "newChatMCPMode"
    static let newChatFixedMCPEnabled = "newChatFixedMCPEnabled"
    static let newChatFixedMCPUseAllServers = "newChatFixedMCPUseAllServers"
    static let newChatFixedMCPServerIDsJSON = "newChatFixedMCPServerIDsJSON"

    // MARK: - Appearance

    static let appAppearanceMode = "appAppearanceMode"
    static let appIconVariant = "appIconVariant"
    static let appFontFamily = "appFontFamily"
    static let codeFontFamily = "codeFontFamily"

    // MARK: - Chat

    static let sendWithCommandEnter = "sendWithCommandEnter"
    static let notifyOnBackgroundResponseCompletion = "notifyOnBackgroundResponseCompletion"
    static let keyboardShortcuts = "keyboardShortcuts.v1"

    // MARK: - Updates

    // Update checker
    static let updateAutoCheckOnLaunch = "updateAutoCheckOnLaunch"
    static let updateAllowPreRelease = "updateAllowPreRelease"

    // MARK: - Extensions

    // Plugin visibility toggles (default: true)
    static let pluginTextToSpeechEnabled = "pluginTextToSpeechEnabled"
    static let pluginSpeechToTextEnabled = "pluginSpeechToTextEnabled"
    static let pluginMistralOCREnabled = "pluginMistralOCREnabled"
    static let pluginDeepSeekOCREnabled = "pluginDeepSeekOCREnabled"
    static let pluginChatNamingEnabled = "pluginChatNamingEnabled"
    static let pluginCloudflareR2UploadEnabled = "pluginCloudflareR2UploadEnabled"

    static let pluginMistralOCRAPIKey = "pluginMistralOCRAPIKey"
    static let pluginDeepSeekOCRAPIKey = "pluginDeepSeekOCRAPIKey"

    // Cloudflare R2 Upload
    static let cloudflareR2AccountID = "cloudflareR2AccountID"
    static let cloudflareR2AccessKeyID = "cloudflareR2AccessKeyID"
    static let cloudflareR2SecretAccessKey = "cloudflareR2SecretAccessKey"
    static let cloudflareR2Bucket = "cloudflareR2Bucket"
    static let cloudflareR2PublicBaseURL = "cloudflareR2PublicBaseURL"
    static let cloudflareR2KeyPrefix = "cloudflareR2KeyPrefix"

    // Chat naming
    static let chatNamingMode = "chatNamingMode"
    static let chatNamingProviderID = "chatNamingProviderID"
    static let chatNamingModelID = "chatNamingModelID"

    // Text to Speech
    static let ttsProvider = "ttsProvider"

    static let ttsOpenAIAPIKey = "ttsOpenAIAPIKey"
    static let ttsOpenAIBaseURL = "ttsOpenAIBaseURL"
    static let ttsOpenAIModel = "ttsOpenAIModel"
    static let ttsOpenAIVoice = "ttsOpenAIVoice"
    static let ttsOpenAIResponseFormat = "ttsOpenAIResponseFormat"
    static let ttsOpenAISpeed = "ttsOpenAISpeed"
    static let ttsOpenAIInstructions = "ttsOpenAIInstructions"

    static let ttsGroqAPIKey = "ttsGroqAPIKey"
    static let ttsGroqBaseURL = "ttsGroqBaseURL"
    static let ttsGroqModel = "ttsGroqModel"
    static let ttsGroqVoice = "ttsGroqVoice"
    static let ttsGroqResponseFormat = "ttsGroqResponseFormat"

    static let ttsElevenLabsAPIKey = "ttsElevenLabsAPIKey"
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

    static let sttOpenAIAPIKey = "sttOpenAIAPIKey"
    static let sttOpenAIBaseURL = "sttOpenAIBaseURL"
    static let sttOpenAIModel = "sttOpenAIModel"
    static let sttOpenAILanguage = "sttOpenAILanguage"
    static let sttOpenAIPrompt = "sttOpenAIPrompt"
    static let sttOpenAITranslateToEnglish = "sttOpenAITranslateToEnglish"
    static let sttOpenAIResponseFormat = "sttOpenAIResponseFormat"
    static let sttOpenAITemperature = "sttOpenAITemperature"
    static let sttOpenAITimestampGranularitiesJSON = "sttOpenAITimestampGranularitiesJSON"

    static let sttGroqAPIKey = "sttGroqAPIKey"
    static let sttGroqBaseURL = "sttGroqBaseURL"
    static let sttGroqModel = "sttGroqModel"
    static let sttGroqLanguage = "sttGroqLanguage"
    static let sttGroqPrompt = "sttGroqPrompt"
    static let sttGroqTranslateToEnglish = "sttGroqTranslateToEnglish"
    static let sttGroqResponseFormat = "sttGroqResponseFormat"
    static let sttGroqTemperature = "sttGroqTemperature"
    static let sttGroqTimestampGranularitiesJSON = "sttGroqTimestampGranularitiesJSON"

    static let sttMistralAPIKey = "sttMistralAPIKey"
    static let sttMistralBaseURL = "sttMistralBaseURL"
    static let sttMistralModel = "sttMistralModel"
    static let sttMistralLanguage = "sttMistralLanguage"
    static let sttMistralPrompt = "sttMistralPrompt"
    static let sttMistralResponseFormat = "sttMistralResponseFormat"
    static let sttMistralTemperature = "sttMistralTemperature"
    static let sttMistralTimestampGranularitiesJSON = "sttMistralTimestampGranularitiesJSON"
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

enum AppIconVariant: String, CaseIterable, Identifiable {
    case roseQuartz = "A"
    case roseDusk = "B"
    case warmIvory = "C"
    case lavenderMist = "D"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .roseQuartz:
            return "Rose Quartz"
        case .roseDusk:
            return "Rose Dusk"
        case .warmIvory:
            return "Warm Ivory"
        case .lavenderMist:
            return "Lavender Mist"
        }
    }

    var icnsName: String {
        "AppIcon\(rawValue)"
    }

    var thumbnailResourceName: String {
        "Icon\(rawValue)"
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

enum ChatNamingMode: String, CaseIterable, Identifiable {
    case firstRoundFixed
    case everyRound

    var id: String { rawValue }

    var label: String {
        switch self {
        case .firstRoundFixed:
            return "First Round Only"
        case .everyRound:
            return "Rename Every Round"
        }
    }
}

enum GeneralSettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case chat
    case shortcuts
    case defaults
    case updates
    case data

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appearance: return "Appearance"
        case .chat: return "Chat"
        case .shortcuts: return "Keyboard Shortcuts"
        case .defaults: return "Defaults"
        case .updates: return "Updates"
        case .data: return "Data"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "textformat"
        case .chat: return "bubble.left.and.bubble.right"
        case .shortcuts: return "command"
        case .defaults: return "sparkles"
        case .updates: return "arrow.triangle.2.circlepath"
        case .data: return "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: return "App icon, theme, and fonts."
        case .chat: return "Send behavior and background-completion notifications."
        case .shortcuts: return "Show and customize keyboard shortcuts."
        case .defaults: return "Model and MCP defaults for new chats."
        case .updates: return "Sparkle checks updates from the appcast feed."
        case .data: return "Inspect and manage local chat data."
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
        case "chat_naming":
            return AppPreferenceKeys.pluginChatNamingEnabled
        case "cloudflare_r2_upload":
            return AppPreferenceKeys.pluginCloudflareR2UploadEnabled
        default:
            return nil
        }
    }

    static func isPluginEnabled(_ pluginID: String, defaults: UserDefaults = .standard) -> Bool {
        guard let key = pluginEnabledPreferenceKey(for: pluginID) else { return true }
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        if pluginID == "chat_naming" || pluginID == "cloudflare_r2_upload" {
            return false
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
