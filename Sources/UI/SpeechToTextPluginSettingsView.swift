import SwiftUI

struct SpeechToTextPluginSettingsView: View {
    @AppStorage(AppPreferenceKeys.sttProvider) var providerRaw = SpeechToTextProvider.groq.rawValue
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) var addRecordingAsFile = false

    @AppStorage(AppPreferenceKeys.sttOpenAIBaseURL) var openAIBaseURL = OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.sttOpenAIModel) var openAIModel = "gpt-4o-mini-transcribe"
    @AppStorage(AppPreferenceKeys.sttOpenAILanguage) var openAILanguage = ""
    @AppStorage(AppPreferenceKeys.sttOpenAIPrompt) var openAIPrompt = ""
    @AppStorage(AppPreferenceKeys.sttOpenAITranslateToEnglish) var openAITranslateToEnglish = false
    @AppStorage(AppPreferenceKeys.sttOpenAIResponseFormat) var openAIResponseFormat = "json"
    @AppStorage(AppPreferenceKeys.sttOpenAITemperature) var openAITemperature = 0.0
    @AppStorage(AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON) var openAITimestampGranularitiesJSON = "[]"

    @AppStorage(AppPreferenceKeys.sttGroqBaseURL) var groqBaseURL = GroqAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.sttGroqModel) var groqModel = "whisper-large-v3-turbo"
    @AppStorage(AppPreferenceKeys.sttGroqLanguage) var groqLanguage = ""
    @AppStorage(AppPreferenceKeys.sttGroqPrompt) var groqPrompt = ""
    @AppStorage(AppPreferenceKeys.sttGroqTranslateToEnglish) var groqTranslateToEnglish = false
    @AppStorage(AppPreferenceKeys.sttGroqResponseFormat) var groqResponseFormat = "json"
    @AppStorage(AppPreferenceKeys.sttGroqTemperature) var groqTemperature = 0.0
    @AppStorage(AppPreferenceKeys.sttGroqTimestampGranularitiesJSON) var groqTimestampGranularitiesJSON = "[]"

    @AppStorage(AppPreferenceKeys.sttMistralBaseURL) var mistralBaseURL = ProviderType.mistral.defaultBaseURL ?? "https://api.mistral.ai/v1"
    @AppStorage(AppPreferenceKeys.sttMistralModel) var mistralModel = "voxtral-mini-latest"
    @AppStorage(AppPreferenceKeys.sttMistralLanguage) var mistralLanguage = ""
    @AppStorage(AppPreferenceKeys.sttMistralPrompt) var mistralPrompt = ""
    @AppStorage(AppPreferenceKeys.sttMistralResponseFormat) var mistralResponseFormat = "json"
    @AppStorage(AppPreferenceKeys.sttMistralTemperature) var mistralTemperature = 0.0
    @AppStorage(AppPreferenceKeys.sttMistralTimestampGranularitiesJSON) var mistralTimestampGranularitiesJSON = "[]"

    @AppStorage(AppPreferenceKeys.sttWhisperKitModel) var whisperKitModel = "base"
    @AppStorage(AppPreferenceKeys.sttWhisperKitLanguage) var whisperKitLanguage = ""
    @AppStorage(AppPreferenceKeys.sttWhisperKitTranslateToEnglish) var whisperKitTranslateToEnglish = false

    @AppStorage(AppPreferenceKeys.sttOpenRouterBaseURL) var openRouterBaseURL = OpenRouterAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.sttOpenRouterModel) var openRouterModel = "openai/whisper-1"
    @AppStorage(AppPreferenceKeys.sttOpenRouterLanguage) var openRouterLanguage = ""
    @AppStorage(AppPreferenceKeys.sttOpenRouterTemperature) var openRouterTemperature = 0.0

    @AppStorage(AppPreferenceKeys.sttElevenLabsBaseURL) var elevenLabsBaseURL = ElevenLabsSTTClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.sttElevenLabsModel) var elevenLabsModel = "scribe_v2"
    @AppStorage(AppPreferenceKeys.sttElevenLabsLanguageCode) var elevenLabsLanguageCode = ""
    @AppStorage(AppPreferenceKeys.sttElevenLabsTagAudioEvents) var elevenLabsTagAudioEvents = true
    @AppStorage(AppPreferenceKeys.sttElevenLabsNoVerbatim) var elevenLabsNoVerbatim = false
    @AppStorage(AppPreferenceKeys.sttElevenLabsDiarize) var elevenLabsDiarize = false
    @AppStorage(AppPreferenceKeys.sttElevenLabsNumSpeakers) var elevenLabsNumSpeakers = 2
    @AppStorage(AppPreferenceKeys.sttElevenLabsTimestampsGranularity) var elevenLabsTimestampsGranularity = "word"
    @AppStorage(AppPreferenceKeys.sttElevenLabsFileFormat) var elevenLabsFileFormat = "other"
    @AppStorage(AppPreferenceKeys.sttElevenLabsTemperature) var elevenLabsTemperature = 0.0

    @State var apiKey = ""
    @State var isKeyVisible = false
    @State var isTesting = false
    @State var statusMessage: String?
    @State var statusIsError = false
    @State var hasLoadedKey = false
    @State var lastPersistedAPIKey = ""
    @State var autoSaveTask: Task<Void, Never>?
    @State var openAIModels: [SpeechProviderModelChoice] = []
    @State var openRouterModels: [SpeechProviderModelChoice] = []
    @State var groqModels: [SpeechProviderModelChoice] = []
    @State var mistralModels: [SpeechProviderModelChoice] = []
    @State var elevenLabsModels: [SpeechProviderModelChoice] = []
    @State var isLoadingModels = false

    var provider: SpeechToTextProvider? {
        SpeechToTextProvider(rawValue: providerRaw)
    }

    var currentAPIKeyPreferenceKey: String? {
        guard let provider else { return nil }
        let preferenceKey = SpeechPluginPreferenceSupport.speechToTextAPIKeyPreferenceKey(for: provider)
        return preferenceKey.isEmpty ? nil : preferenceKey
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Provider") {
                JinSettingsPickerRow("Provider", selection: $providerRaw) {
                    ForEach(SpeechToTextProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .onChange(of: providerRaw) { oldProviderRaw, _ in
                    autoSaveTask?.cancel()
                    if SpeechToTextProvider(rawValue: oldProviderRaw)?.requiresAPIKey == true {
                        persistAPIKeyIfNeeded(forProviderRaw: oldProviderRaw, showSavedStatus: false)
                    }
                    Task { await loadExistingKeyAndMaybeModels() }
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }

                JinSettingsToggleRow("Add recording as file", isOn: $addRecordingAsFile)
                    .help("Attach microphone recordings as audio files for models that support audio input instead of transcribing.")
            }

            if provider?.requiresAPIKey != false {
                JinSettingsSection(
                    "API Key",
                    detail: "Stored locally on this Mac. Changes save automatically."
                ) {
                    JinSettingsSecureFieldRow(
                        "API Key",
                        text: $apiKey,
                        isRevealed: $isKeyVisible,
                        revealHelp: "Show API key",
                        concealHelp: "Hide API key"
                    )

                    PluginCredentialActionsView(
                        canTestConnection: !trimmedAPIKey.isEmpty,
                        canClear: true,
                        isTesting: isTesting,
                        showsProgress: isTesting || isLoadingModels,
                        statusMessage: statusMessage,
                        statusIsError: statusIsError,
                        spacing: 12,
                        onTestConnection: testConnection,
                        onClear: clearKey
                    )
                }
            }

            providerSpecificSettings
        }
        .navigationTitle("Speech to Text")
        .task {
            await loadExistingKeyAndMaybeModels()
            hasLoadedKey = true
        }
        .onChange(of: apiKey) { _, _ in
            guard hasLoadedKey else { return }
            scheduleAutoSave()
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
    }
}
