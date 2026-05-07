import Foundation

// MARK: - Speech Controls

extension ChatView {

    func refreshExtensionCredentialsStatus() async {
        let status = ChatConversationStateSupport.resolveExtensionCredentialStatus()

        await MainActor.run {
            mistralOCRConfigured = status.mistralOCRConfigured
            mineruOCRConfigured = status.mineruOCRConfigured
            deepSeekOCRConfigured = status.deepSeekOCRConfigured
            openRouterOCRConfigured = status.openRouterOCRConfigured
            firecrawlOCRConfigured = status.firecrawlOCRConfigured
            textToSpeechConfigured = status.textToSpeechConfigured
            speechToTextConfigured = status.speechToTextConfigured
            webSearchPluginConfigured = status.webSearchPluginConfigured

            mistralOCRPluginEnabled = status.mistralOCRPluginEnabled
            mineruOCRPluginEnabled = status.mineruOCRPluginEnabled
            deepSeekOCRPluginEnabled = status.deepSeekOCRPluginEnabled
            openRouterOCRPluginEnabled = status.openRouterOCRPluginEnabled
            firecrawlOCRPluginEnabled = status.firecrawlOCRPluginEnabled
            textToSpeechPluginEnabled = status.textToSpeechPluginEnabled
            speechToTextPluginEnabled = status.speechToTextPluginEnabled
            webSearchPluginEnabled = status.webSearchPluginEnabled

            if !status.textToSpeechPluginEnabled {
                ttsPlaybackManager.stop()
            }
            if !status.speechToTextPluginEnabled {
                speechToTextManager.cancelAndCleanup()
            }
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
                        errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                        showingError = true
                    }
                )
            } catch {
                errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                showingError = true
            }
        }
    }

    func stopSpeakAssistantMessage(_ messageEntity: MessageEntity) {
        ttsPlaybackManager.stop(messageID: messageEntity.id)
    }
}
