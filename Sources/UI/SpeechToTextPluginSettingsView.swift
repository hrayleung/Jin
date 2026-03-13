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

    @State var apiKey = ""
    @State var isKeyVisible = false
    @State var isTesting = false
    @State var statusMessage: String?
    @State var statusIsError = false
    @State var hasLoadedKey = false
    @State var lastPersistedAPIKey = ""
    @State var autoSaveTask: Task<Void, Never>?

    var provider: SpeechToTextProvider? {
        SpeechToTextProvider(rawValue: providerRaw)
    }

    var currentAPIKeyPreferenceKey: String? {
        guard let provider else { return nil }
        switch provider {
        case .openai:
            return AppPreferenceKeys.sttOpenAIAPIKey
        case .groq:
            return AppPreferenceKeys.sttGroqAPIKey
        case .mistral:
            return AppPreferenceKeys.sttMistralAPIKey
        case .whisperKit:
            return nil
        }
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(SpeechToTextProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerRaw) { oldProviderRaw, _ in
                    autoSaveTask?.cancel()
                    if SpeechToTextProvider(rawValue: oldProviderRaw)?.requiresAPIKey == true {
                        persistAPIKeyIfNeeded(forProviderRaw: oldProviderRaw, showSavedStatus: false)
                    }
                    Task { await loadExistingKey() }
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }

                Toggle("Add recording as file", isOn: $addRecordingAsFile)
                    .help("Attach microphone recordings as audio files for models that support audio input instead of transcribing.")

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

                        if isTesting {
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
        .navigationTitle("Speech to Text")
        .task {
            await loadExistingKey()
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
