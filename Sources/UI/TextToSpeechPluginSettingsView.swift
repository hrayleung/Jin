import SwiftUI
import AVFoundation

struct TextToSpeechPluginSettingsView: View {
    @AppStorage(AppPreferenceKeys.ttsMiniPlayerEnabled) var miniPlayerEnabled = true
    @AppStorage(AppPreferenceKeys.ttsProvider) var providerRaw = TextToSpeechProvider.openai.rawValue

    @AppStorage(AppPreferenceKeys.ttsOpenAIBaseURL) var openAIBaseURL = OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsOpenAIModel) var openAIModel = "gpt-4o-mini-tts"
    @AppStorage(AppPreferenceKeys.ttsOpenAIVoice) var openAIVoice = "alloy"
    @AppStorage(AppPreferenceKeys.ttsOpenAIResponseFormat) var openAIResponseFormat = "mp3"
    @AppStorage(AppPreferenceKeys.ttsOpenAISpeed) var openAISpeed = 1.0
    @AppStorage(AppPreferenceKeys.ttsOpenAIInstructions) var openAIInstructions = ""

    @AppStorage(AppPreferenceKeys.ttsGroqBaseURL) var groqBaseURL = GroqAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsGroqModel) var groqModel = "canopylabs/orpheus-v1-english"
    @AppStorage(AppPreferenceKeys.ttsGroqVoice) var groqVoice = "troy"
    @AppStorage(AppPreferenceKeys.ttsGroqResponseFormat) var groqResponseFormat = "wav"

    @AppStorage(AppPreferenceKeys.ttsElevenLabsBaseURL) var elevenLabsBaseURL = ElevenLabsTTSClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsElevenLabsModelID) var elevenLabsModelID = "eleven_multilingual_v2"
    @AppStorage(AppPreferenceKeys.ttsElevenLabsVoiceID) var elevenLabsVoiceID = ""
    @AppStorage(AppPreferenceKeys.ttsElevenLabsOutputFormat) var elevenLabsOutputFormat = "mp3_44100_128"
    @AppStorage(AppPreferenceKeys.ttsElevenLabsOptimizeStreamingLatency) var elevenLabsOptimizeStreamingLatency = 0
    @AppStorage(AppPreferenceKeys.ttsElevenLabsEnableLogging) var elevenLabsEnableLogging = true
    @AppStorage(AppPreferenceKeys.ttsElevenLabsStability) var elevenLabsStability = 0.5
    @AppStorage(AppPreferenceKeys.ttsElevenLabsSimilarityBoost) var elevenLabsSimilarityBoost = 0.75
    @AppStorage(AppPreferenceKeys.ttsElevenLabsStyle) var elevenLabsStyle = 0.0
    @AppStorage(AppPreferenceKeys.ttsElevenLabsUseSpeakerBoost) var elevenLabsUseSpeakerBoost = true

    @AppStorage(AppPreferenceKeys.ttsTTSKitModel) var ttsKitModel = TTSKitModelCatalog.defaultModelID
    @AppStorage(AppPreferenceKeys.ttsTTSKitVoice) var ttsKitVoice = ""
    @AppStorage(AppPreferenceKeys.ttsTTSKitLanguage) var ttsKitLanguage = ""
    @AppStorage(AppPreferenceKeys.ttsTTSKitPlaybackMode) var ttsKitPlaybackMode = TTSKitPlaybackMode.auto.rawValue
    @AppStorage(AppPreferenceKeys.ttsTTSKitStyleInstruction) var ttsKitStyleInstruction = ""

    @State var apiKey = ""
    @State var isKeyVisible = false
    @State var isTesting = false
    @State var statusMessage: String?
    @State var statusIsError = false
    @State var hasLoadedKey = false
    @State var lastPersistedAPIKey = ""
    @State var autoSaveTask: Task<Void, Never>?

    @State var elevenLabsVoices: [ElevenLabsTTSClient.Voice] = []
    @State var isLoadingVoices = false
    @State var voicePreviewPlayer: AVAudioPlayer?
    @State var isPlayingVoicePreview = false

    var provider: TextToSpeechProvider? {
        TextToSpeechProvider(rawValue: providerRaw)
    }

    var currentAPIKeyPreferenceKey: String? {
        guard let provider else { return nil }
        switch provider {
        case .elevenlabs:
            return AppPreferenceKeys.ttsElevenLabsAPIKey
        case .openai:
            return AppPreferenceKeys.ttsOpenAIAPIKey
        case .groq:
            return AppPreferenceKeys.ttsGroqAPIKey
        case .whisperKit:
            return nil
        }
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Show floating mini player", isOn: $miniPlayerEnabled)
                    .help("Show a floating mini player at the top of the chat when speech is playing.")
            }

            Section("Provider") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(TextToSpeechProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerRaw) { oldProviderRaw, _ in
                    autoSaveTask?.cancel()
                    if TextToSpeechProvider(rawValue: oldProviderRaw)?.requiresAPIKey == true {
                        persistAPIKeyIfNeeded(forProviderRaw: oldProviderRaw, showSavedStatus: false)
                    }
                    Task { await loadExistingKeyAndMaybeVoices() }
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }
            }

            if provider?.requiresAPIKey != false {
            Section("API Key") {
                HStack(spacing: 8) {
                    Group {
                        if isKeyVisible {
                            TextField("API Key", text: $apiKey)
                                .textContentType(.password)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textContentType(.password)
                        }
                    }

                    Button {
                        isKeyVisible.toggle()
                    } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(isKeyVisible ? "Hide API key" : "Show API key")
                    .disabled(apiKey.isEmpty)
                }

                HStack(spacing: 12) {
                    Button("Test Connection") { testConnection() }
                        .disabled(trimmedAPIKey.isEmpty || isTesting)

                    Button("Clear", role: .destructive) { clearKey() }
                        .disabled(isTesting)

                    Spacer()

                    if isTesting || isLoadingVoices {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                }
            }
            }

            providerSpecificSettings
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("Text to Speech")
        .task {
            await loadExistingKeyAndMaybeVoices()
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
