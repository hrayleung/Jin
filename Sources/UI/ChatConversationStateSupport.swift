import Foundation
import SwiftData

struct ChatExtensionCredentialStatus {
    let mistralOCRConfigured: Bool
    let mineruOCRConfigured: Bool
    let deepSeekOCRConfigured: Bool
    let textToSpeechConfigured: Bool
    let speechToTextConfigured: Bool
    let webSearchPluginConfigured: Bool
    let mistralOCRPluginEnabled: Bool
    let mineruOCRPluginEnabled: Bool
    let deepSeekOCRPluginEnabled: Bool
    let textToSpeechPluginEnabled: Bool
    let speechToTextPluginEnabled: Bool
    let webSearchPluginEnabled: Bool
}

enum ChatConversationStateSupport {
    @MainActor
    static func ensureModelThreadsInitializedIfNeeded(
        conversationEntity: ConversationEntity,
        activeThreadID: inout UUID?,
        modelContext: ModelContext,
        activeModelThread: () -> ConversationModelThreadEntity?,
        sortedModelThreads: () -> [ConversationModelThreadEntity]
    ) {
        var didMutate = false

        if conversationEntity.modelThreads.isEmpty {
            let controlsData = conversationEntity.modelConfigData
            let thread = ConversationModelThreadEntity(
                providerID: conversationEntity.providerID,
                modelID: conversationEntity.modelID,
                modelConfigData: controlsData,
                displayOrder: 0,
                isSelected: true,
                isPrimary: true
            )
            thread.conversation = conversationEntity
            conversationEntity.modelThreads.append(thread)
            conversationEntity.activeThreadID = thread.id
            activeThreadID = thread.id
            didMutate = true
        }

        guard let fallbackThread = activeModelThread() ?? sortedModelThreads().first else { return }
        for message in conversationEntity.messages where message.contextThreadID == nil {
            message.contextThreadID = fallbackThread.id
            didMutate = true
        }

        if let currentActive = conversationEntity.activeThreadID,
           !sortedModelThreads().contains(where: { $0.id == currentActive }) {
            conversationEntity.activeThreadID = fallbackThread.id
            activeThreadID = fallbackThread.id
            didMutate = true
        }

        if sortedModelThreads().filter(\.isSelected).isEmpty,
           let first = sortedModelThreads().first {
            first.isSelected = true
            didMutate = true
        }

        if didMutate {
            try? modelContext.save()
        }
    }

    static func syncActiveThreadSelection(
        activeModelThread: ConversationModelThreadEntity?,
        sortedModelThreads: [ConversationModelThreadEntity],
        synchronizeLegacyConversationModelFields: (ConversationModelThreadEntity) -> Void
    ) {
        if let current = activeModelThread {
            synchronizeLegacyConversationModelFields(current)
            return
        }

        if let first = sortedModelThreads.first {
            synchronizeLegacyConversationModelFields(first)
        }
    }

    static func loadControlsFromConversation(
        conversationEntity: ConversationEntity,
        activeThread: ConversationModelThreadEntity?
    ) -> GenerationControls {
        let controlsData = activeThread?.modelConfigData ?? conversationEntity.modelConfigData
        if let decoded = try? JSONDecoder().decode(GenerationControls.self, from: controlsData) {
            return decoded
        }
        return GenerationControls()
    }

    static func persistControlsToConversation(
        controls: GenerationControls,
        activeThread: ConversationModelThreadEntity?,
        storedGenerationControls: (ConversationModelThreadEntity) -> GenerationControls?,
        conversationEntity: ConversationEntity,
        modelContext: ModelContext
    ) throws {
        var persistedControls = controls
        if let activeThread,
           let storedControls = storedGenerationControls(activeThread) {
            persistedControls.codexResumeThreadID = storedControls.codexResumeThreadID
            persistedControls.codexPendingRollbackTurns = storedControls.codexPendingRollbackTurns
            persistedControls.claudeManagedSessionID = storedControls.claudeManagedSessionID
            persistedControls.claudeManagedSessionModelID = storedControls.claudeManagedSessionModelID
            persistedControls.claudeManagedPendingCustomToolResults = storedControls.claudeManagedPendingCustomToolResults
        }

        let data = try JSONEncoder().encode(persistedControls)
        if let activeThread {
            activeThread.modelConfigData = data
            activeThread.updatedAt = Date()
            conversationEntity.modelConfigData = data
        } else {
            conversationEntity.modelConfigData = data
        }
        try modelContext.save()
    }

    static func resolveExtensionCredentialStatus(
        defaults: UserDefaults = .standard
    ) -> ChatExtensionCredentialStatus {
        func hasStoredKey(_ key: String) -> Bool {
            let trimmed = (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }

        let mistralConfigured = hasStoredKey(AppPreferenceKeys.pluginMistralOCRAPIKey)
        let mineruConfigured = hasStoredKey(AppPreferenceKeys.pluginMineruOCRAPIToken)
        let deepSeekConfigured = hasStoredKey(AppPreferenceKeys.pluginDeepSeekOCRAPIKey)

        let ttsProvider = try? SpeechPluginConfigFactory.currentTTSProvider(defaults: defaults)
        let sttProvider = try? SpeechPluginConfigFactory.currentSTTProvider(defaults: defaults)

        let ttsKeyConfigured = {
            guard let ttsProvider else { return false }
            if !ttsProvider.requiresAPIKey { return true }
            let key: String
            switch ttsProvider {
            case .elevenlabs:
                key = AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:
                key = AppPreferenceKeys.ttsOpenAIAPIKey
            case .groq:
                key = AppPreferenceKeys.ttsGroqAPIKey
            case .whisperKit:
                return true
            }
            return hasStoredKey(key)
        }()

        let sttKeyConfigured = {
            guard let sttProvider else { return false }
            if !sttProvider.requiresAPIKey { return true }
            let key: String
            switch sttProvider {
            case .openai:
                key = AppPreferenceKeys.sttOpenAIAPIKey
            case .groq:
                key = AppPreferenceKeys.sttGroqAPIKey
            case .mistral:
                key = AppPreferenceKeys.sttMistralAPIKey
            case .whisperKit:
                return true
            }
            return hasStoredKey(key)
        }()

        let ttsConfigured: Bool
        if ttsProvider == .elevenlabs {
            let voiceID = (defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ttsConfigured = ttsKeyConfigured && !voiceID.isEmpty
        } else {
            ttsConfigured = ttsKeyConfigured
        }

        let mistralEnabled = AppPreferences.isPluginEnabled("mistral_ocr", defaults: defaults)
        let mineruEnabled = AppPreferences.isPluginEnabled("mineru_ocr", defaults: defaults)
        let deepSeekEnabled = AppPreferences.isPluginEnabled("deepseek_ocr", defaults: defaults)
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
            textToSpeechConfigured: ttsConfigured,
            speechToTextConfigured: sttKeyConfigured,
            webSearchPluginConfigured: webSearchConfigured,
            mistralOCRPluginEnabled: mistralEnabled,
            mineruOCRPluginEnabled: mineruEnabled,
            deepSeekOCRPluginEnabled: deepSeekEnabled,
            textToSpeechPluginEnabled: ttsEnabled,
            speechToTextPluginEnabled: sttEnabled,
            webSearchPluginEnabled: webSearchEnabled
        )
    }
}
