import Foundation
import SwiftData

struct ChatExtensionCredentialStatus {
    let mistralOCRConfigured: Bool
    let mineruOCRConfigured: Bool
    let deepSeekOCRConfigured: Bool
    let openRouterOCRConfigured: Bool
    let firecrawlOCRConfigured: Bool
    let textToSpeechConfigured: Bool
    let speechToTextConfigured: Bool
    let webSearchPluginConfigured: Bool
    let mistralOCRPluginEnabled: Bool
    let mineruOCRPluginEnabled: Bool
    let deepSeekOCRPluginEnabled: Bool
    let openRouterOCRPluginEnabled: Bool
    let firecrawlOCRPluginEnabled: Bool
    let textToSpeechPluginEnabled: Bool
    let speechToTextPluginEnabled: Bool
    let webSearchPluginEnabled: Bool
}

enum ChatConversationStateSupport {
    static func resolveExtensionCredentialStatus(
        defaults: UserDefaults = .standard
    ) -> ChatExtensionCredentialStatus {
        func hasStoredKey(_ key: String) -> Bool {
            defaults.string(forKey: key)?.trimmedNonEmpty != nil
        }

        let mistralConfigured = hasStoredKey(AppPreferenceKeys.pluginMistralOCRAPIKey)
        let mineruConfigured = hasStoredKey(AppPreferenceKeys.pluginMineruOCRAPIToken)
        let deepSeekConfigured = hasStoredKey(AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
        let openRouterConfigured = hasStoredKey(AppPreferenceKeys.pluginOpenRouterOCRAPIKey)
        let firecrawlConfigured = hasStoredKey(AppPreferenceKeys.pluginWebSearchFirecrawlAPIKey)
            && ((try? CloudflareR2Configuration.load(from: defaults).validated()) != nil)

        let ttsProvider = try? SpeechPluginConfigFactory.currentTTSProvider(defaults: defaults)
        let sttProvider = try? SpeechPluginConfigFactory.currentSTTProvider(defaults: defaults)

        let ttsKeyConfigured = {
            guard let ttsProvider else { return false }
            let key: String
            switch ttsProvider {
            case .elevenlabs:
                key = AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:
                key = AppPreferenceKeys.ttsOpenAIAPIKey
            case .openRouter:
                key = AppPreferenceKeys.ttsOpenRouterAPIKey
            case .groq:
                key = AppPreferenceKeys.ttsGroqAPIKey
            case .xiaomiMiMo:
                key = AppPreferenceKeys.ttsMiMoAPIKey
            }
            return hasStoredKey(key)
        }()

        let sttKeyConfigured = {
            guard let sttProvider else { return false }
            let key: String
            switch sttProvider {
            case .openai:
                key = AppPreferenceKeys.sttOpenAIAPIKey
            case .openRouter:
                key = AppPreferenceKeys.sttOpenRouterAPIKey
            case .groq:
                key = AppPreferenceKeys.sttGroqAPIKey
            case .mistral:
                key = AppPreferenceKeys.sttMistralAPIKey
            case .elevenlabs:
                key = AppPreferenceKeys.sttElevenLabsAPIKey
            }
            return hasStoredKey(key)
        }()

        let ttsConfigured: Bool
        if ttsProvider == .elevenlabs {
            let hasVoiceID = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID)?.trimmedNonEmpty != nil
            ttsConfigured = ttsKeyConfigured && hasVoiceID
        } else {
            ttsConfigured = ttsKeyConfigured
        }

        let mistralEnabled = AppPreferences.isPluginEnabled("mistral_ocr", defaults: defaults)
        let mineruEnabled = AppPreferences.isPluginEnabled("mineru_ocr", defaults: defaults)
        let deepSeekEnabled = AppPreferences.isPluginEnabled("deepseek_ocr", defaults: defaults)
        let openRouterEnabled = AppPreferences.isPluginEnabled("openrouter_ocr", defaults: defaults)
        let firecrawlEnabled = AppPreferences.isPluginEnabled("firecrawl_ocr", defaults: defaults)
        let ttsEnabled = AppPreferences.isPluginEnabled("text_to_speech", defaults: defaults)
        let sttEnabled = AppPreferences.isPluginEnabled("speech_to_text", defaults: defaults)
        let webSearchSettings = WebSearchPluginSettingsStore.load(defaults: defaults)
        let webSearchEnabled = webSearchSettings.isEnabled
        let webSearchConfigured = SearchPluginProvider.allCases.contains {
            webSearchSettings.hasConfiguredCredential(for: $0)
        }

        return ChatExtensionCredentialStatus(
            mistralOCRConfigured: mistralConfigured,
            mineruOCRConfigured: mineruConfigured,
            deepSeekOCRConfigured: deepSeekConfigured,
            openRouterOCRConfigured: openRouterConfigured,
            firecrawlOCRConfigured: firecrawlConfigured,
            textToSpeechConfigured: ttsConfigured,
            speechToTextConfigured: sttKeyConfigured,
            webSearchPluginConfigured: webSearchConfigured,
            mistralOCRPluginEnabled: mistralEnabled,
            mineruOCRPluginEnabled: mineruEnabled,
            deepSeekOCRPluginEnabled: deepSeekEnabled,
            openRouterOCRPluginEnabled: openRouterEnabled,
            firecrawlOCRPluginEnabled: firecrawlEnabled,
            textToSpeechPluginEnabled: ttsEnabled,
            speechToTextPluginEnabled: sttEnabled,
            webSearchPluginEnabled: webSearchEnabled
        )
    }
}
