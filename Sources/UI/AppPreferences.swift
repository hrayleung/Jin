import Foundation

enum AppPreferences {
    static func boolValue(forKey key: String, default defaultValue: Bool, defaults: UserDefaults = .standard) -> Bool {
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        return defaultValue
    }

    static func pluginEnabledPreferenceKey(for pluginID: String) -> String? {
        switch pluginID {
        case "text_to_speech":
            return AppPreferenceKeys.pluginTextToSpeechEnabled
        case "speech_to_text":
            return AppPreferenceKeys.pluginSpeechToTextEnabled
        case "mistral_ocr":
            return AppPreferenceKeys.pluginMistralOCREnabled
        case "mineru_ocr":
            return AppPreferenceKeys.pluginMineruOCREnabled
        case "deepseek_ocr":
            return AppPreferenceKeys.pluginDeepSeekOCREnabled
        case "openrouter_ocr":
            return AppPreferenceKeys.pluginOpenRouterOCREnabled
        case "firecrawl_ocr":
            return AppPreferenceKeys.pluginFirecrawlOCREnabled
        case "chat_naming":
            return AppPreferenceKeys.pluginChatNamingEnabled
        case "cloudflare_r2_upload":
            return AppPreferenceKeys.pluginCloudflareR2UploadEnabled
        case "web_search_builtin":
            return AppPreferenceKeys.pluginWebSearchEnabled
        case "agent_mode":
            return AppPreferenceKeys.agentModeEnabled
        default:
            return nil
        }
    }

    static func isPluginEnabled(_ pluginID: String, defaults: UserDefaults = .standard) -> Bool {
        guard let key = pluginEnabledPreferenceKey(for: pluginID) else { return true }
        if let value = defaults.object(forKey: key) as? Bool {
            return value
        }
        if pluginID == "chat_naming" || pluginID == "cloudflare_r2_upload" || pluginID == "agent_mode" {
            return false
        }
        return true
    }

    static func setPluginEnabled(_ enabled: Bool, for pluginID: String, defaults: UserDefaults = .standard) {
        guard let key = pluginEnabledPreferenceKey(for: pluginID) else { return }
        defaults.set(enabled, forKey: key)
    }

    static func decodeStringArrayJSON(_ value: String) -> [String] {
        guard let trimmed = value.trimmedNonEmpty,
              let data = trimmed.data(using: .utf8) else { return [] }
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
