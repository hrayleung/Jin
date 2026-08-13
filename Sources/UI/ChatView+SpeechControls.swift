import Foundation

// MARK: - Speech Controls

extension ChatView {

    var mistralOCRConfigured: Bool { extensionCredentialStore.status.mistralOCRConfigured }
    var mineruOCRConfigured: Bool { extensionCredentialStore.status.mineruOCRConfigured }
    var deepSeekOCRConfigured: Bool { extensionCredentialStore.status.deepSeekOCRConfigured }
    var openRouterOCRConfigured: Bool { extensionCredentialStore.status.openRouterOCRConfigured }
    var firecrawlOCRConfigured: Bool { extensionCredentialStore.status.firecrawlOCRConfigured }
    var textToSpeechConfigured: Bool { extensionCredentialStore.status.textToSpeechConfigured }
    var speechToTextConfigured: Bool { extensionCredentialStore.status.speechToTextConfigured }
    var webSearchPluginConfigured: Bool { extensionCredentialStore.status.webSearchPluginConfigured }

    var mistralOCRPluginEnabled: Bool { extensionCredentialStore.status.mistralOCRPluginEnabled }
    var mineruOCRPluginEnabled: Bool { extensionCredentialStore.status.mineruOCRPluginEnabled }
    var deepSeekOCRPluginEnabled: Bool { extensionCredentialStore.status.deepSeekOCRPluginEnabled }
    var openRouterOCRPluginEnabled: Bool { extensionCredentialStore.status.openRouterOCRPluginEnabled }
    var firecrawlOCRPluginEnabled: Bool { extensionCredentialStore.status.firecrawlOCRPluginEnabled }
    var textToSpeechPluginEnabled: Bool { extensionCredentialStore.status.textToSpeechPluginEnabled }
    var speechToTextPluginEnabled: Bool { extensionCredentialStore.status.speechToTextPluginEnabled }
    var webSearchPluginEnabled: Bool { extensionCredentialStore.status.webSearchPluginEnabled }

    func handleExtensionCredentialStatusSideEffects(
        previous: ChatExtensionCredentialStatus,
        current: ChatExtensionCredentialStatus
    ) {
        if previous.textToSpeechPluginEnabled, !current.textToSpeechPluginEnabled {
            ttsPlaybackManager.stop()
        }
        if previous.speechToTextPluginEnabled, !current.speechToTextPluginEnabled {
            speechToTextManager.cancelAndCleanup()
        }
    }

    func currentSpeechToTextTranscriptionConfig() async throws -> SpeechToTextManager.TranscriptionConfig {
        try SpeechPluginConfigFactory.speechToTextConfig()
    }

    func toggleSpeakAssistantMessage(_ messageEntity: MessageEntity, text: String) {
        Task { @MainActor in
            guard textToSpeechPluginEnabled else { return }

            let provider = try? SpeechPluginConfigFactory.currentTTSProvider()

            do {
                let config = try SpeechPluginConfigFactory.textToSpeechConfig()
                let context = TextToSpeechPlaybackManager.PlaybackContext(
                    conversationID: conversationEntity.id,
                    conversationTitle: conversationEntity.title,
                    textPreview: String(text.prefix(80))
                )
                ttsPlaybackManager.toggleSpeak(
                    messageID: messageEntity.id,
                    text: text,
                    config: config,
                    context: context,
                    onError: { error in
                        presentError(SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider))
                    }
                )
            } catch {
                presentError(SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider))
            }
        }
    }

    func stopSpeakAssistantMessage(_ messageEntity: MessageEntity) {
        ttsPlaybackManager.stop(messageID: messageEntity.id)
    }
}
