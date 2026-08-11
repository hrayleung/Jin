import SwiftUI
import AVFoundation

struct TextToSpeechPluginSettingsView: View {
    @AppStorage(AppPreferenceKeys.ttsMiniPlayerEnabled) var miniPlayerEnabled = true
    @AppStorage(AppPreferenceKeys.ttsProvider) var providerRaw = TextToSpeechProvider.openai.rawValue
    @AppStorage(AppPreferenceKeys.ttsLowLatencyStreaming) var lowLatencyStreaming = true

    @AppStorage(AppPreferenceKeys.ttsOpenAIBaseURL) var openAIBaseURL = OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsOpenAIModel) var openAIModel = SpeechProviderModelCatalog.defaultOpenAITextToSpeechModelID
    @AppStorage(AppPreferenceKeys.ttsOpenAIVoice) var openAIVoice = "alloy"
    @AppStorage(AppPreferenceKeys.ttsOpenAIResponseFormat) var openAIResponseFormat = "mp3"
    @AppStorage(AppPreferenceKeys.ttsOpenAISpeed) var openAISpeed = 1.0
    @AppStorage(AppPreferenceKeys.ttsOpenAIInstructions) var openAIInstructions = ""

    @AppStorage(AppPreferenceKeys.ttsGroqBaseURL) var groqBaseURL = GroqAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsGroqModel) var groqModel = SpeechProviderModelCatalog.defaultGroqTextToSpeechModelID
    @AppStorage(AppPreferenceKeys.ttsGroqVoice) var groqVoice = "troy"
    @AppStorage(AppPreferenceKeys.ttsGroqResponseFormat) var groqResponseFormat = "wav"

    @AppStorage(AppPreferenceKeys.ttsMiMoBaseURL) var miMoBaseURL = MiMoAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsMiMoModel) var miMoModel = MiMoAudioClient.Constants.defaultModel
    @AppStorage(AppPreferenceKeys.ttsMiMoVoice) var miMoVoice = MiMoAudioClient.Constants.defaultVoice
    @AppStorage(AppPreferenceKeys.ttsMiMoResponseFormat) var miMoResponseFormat = MiMoAudioClient.Constants.defaultResponseFormat
    @AppStorage(AppPreferenceKeys.ttsMiMoStyleInstruction) var miMoStyleInstruction = ""
    @AppStorage(AppPreferenceKeys.ttsMiMoVoiceCloneSamplePath) var miMoVoiceCloneSamplePath = ""

    @AppStorage(AppPreferenceKeys.ttsOpenRouterBaseURL) var openRouterBaseURL = OpenRouterAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsOpenRouterModel) var openRouterModel = SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID
    @AppStorage(AppPreferenceKeys.ttsOpenRouterVoice) var openRouterVoice = "Zephyr"
    @AppStorage(AppPreferenceKeys.ttsOpenRouterResponseFormat) var openRouterResponseFormat = "mp3"

    @AppStorage(AppPreferenceKeys.ttsMistralBaseURL) var mistralBaseURL = MistralTTSClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsMistralModel) var mistralModel = SpeechProviderModelCatalog.defaultMistralTextToSpeechModelID
    @AppStorage(AppPreferenceKeys.ttsMistralVoiceID) var mistralVoiceID = ""
    @AppStorage(AppPreferenceKeys.ttsMistralResponseFormat) var mistralResponseFormat = MistralTTSClient.Constants.defaultResponseFormat

    @AppStorage(AppPreferenceKeys.ttsElevenLabsBaseURL) var elevenLabsBaseURL = ElevenLabsTTSClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsElevenLabsModelID) var elevenLabsModelID = SpeechProviderModelCatalog.defaultElevenLabsTextToSpeechModelID
    @AppStorage(AppPreferenceKeys.ttsElevenLabsVoiceID) var elevenLabsVoiceID = ""
    @AppStorage(AppPreferenceKeys.ttsElevenLabsOutputFormat) var elevenLabsOutputFormat = "mp3_44100_128"
    @AppStorage(AppPreferenceKeys.ttsElevenLabsOptimizeStreamingLatency) var elevenLabsOptimizeStreamingLatency = 0
    @AppStorage(AppPreferenceKeys.ttsElevenLabsEnableLogging) var elevenLabsEnableLogging = true
    @AppStorage(AppPreferenceKeys.ttsElevenLabsStability) var elevenLabsStability = 0.5
    @AppStorage(AppPreferenceKeys.ttsElevenLabsSimilarityBoost) var elevenLabsSimilarityBoost = 0.75
    @AppStorage(AppPreferenceKeys.ttsElevenLabsStyle) var elevenLabsStyle = 0.0
    @AppStorage(AppPreferenceKeys.ttsElevenLabsUseSpeakerBoost) var elevenLabsUseSpeakerBoost = true
    @AppStorage(AppPreferenceKeys.ttsElevenLabsSpeed) var elevenLabsSpeed = 1.0

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
    @State var miMoModels: [SpeechProviderModelChoice] = []
    @State var mistralModels: [SpeechProviderModelChoice] = []
    @State var mistralVoices: [MistralTTSClient.Voice] = []
    /// Voice catalogs OpenRouter reports per speech model, keyed by model ID.
    @State var openRouterModelVoices: [String: [String]] = [:]
    @State var elevenLabsVoices: [ElevenLabsTTSClient.Voice] = []
    @State var elevenLabsModels: [ElevenLabsTTSClient.Model] = []
    @State var isLoadingModels = false
    @State var isLoadingVoices = false
    @State var voicePreviewPlayer: AVAudioPlayer?
    @State var isPlayingVoicePreview = false

    var provider: TextToSpeechProvider? {
        TextToSpeechProvider(rawValue: providerRaw)
    }

    var currentAPIKeyPreferenceKey: String? {
        guard let provider else { return nil }
        let preferenceKey = SpeechPluginPreferenceSupport.textToSpeechAPIKeyPreferenceKey(for: provider)
        return preferenceKey.isEmpty ? nil : preferenceKey
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection("Playback") {
                JinSettingsToggleRow("Show floating mini player", isOn: $miniPlayerEnabled)

                JinSettingsToggleRow(
                    "Low-latency streaming",
                    supportingText: streamingSupportingText,
                    isOn: $lowLatencyStreaming
                )
                .disabled(!supportsStreaming)
            }

            JinSettingsSection("Provider") {
                JinSettingsPickerRow("Provider", selection: $providerRaw) {
                    ForEach(TextToSpeechProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .onChange(of: providerRaw) { oldProviderRaw, _ in
                    autoSaveTask?.cancel()
                    persistAPIKeyIfNeeded(forProviderRaw: oldProviderRaw, showSavedStatus: false)
                    Task { await loadExistingKeyAndMaybeProviderResources() }
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }
            }

            JinSettingsSection("API Key") {
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
                    showsProgress: isTesting || isLoadingModels || isLoadingVoices,
                    statusMessage: statusMessage,
                    statusIsError: statusIsError,
                    spacing: 12,
                    onTestConnection: testConnection,
                    onClear: clearKey
                )
            }

            providerSpecificSettings
        }
        .navigationTitle("Text to Speech")
        .task {
            await loadExistingKeyAndMaybeProviderResources()
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
