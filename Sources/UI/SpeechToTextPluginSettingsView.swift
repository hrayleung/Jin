import SwiftUI

struct SpeechToTextPluginSettingsView: View {
    @AppStorage(AppPreferenceKeys.sttProvider) private var providerRaw = SpeechToTextProvider.groq.rawValue
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) private var addRecordingAsFile = false

    @AppStorage(AppPreferenceKeys.sttOpenAIBaseURL) private var openAIBaseURL = OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.sttOpenAIModel) private var openAIModel = "gpt-4o-mini-transcribe"
    @AppStorage(AppPreferenceKeys.sttOpenAILanguage) private var openAILanguage = ""
    @AppStorage(AppPreferenceKeys.sttOpenAIPrompt) private var openAIPrompt = ""
    @AppStorage(AppPreferenceKeys.sttOpenAITranslateToEnglish) private var openAITranslateToEnglish = false
    @AppStorage(AppPreferenceKeys.sttOpenAIResponseFormat) private var openAIResponseFormat = "json"
    @AppStorage(AppPreferenceKeys.sttOpenAITemperature) private var openAITemperature = 0.0
    @AppStorage(AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON) private var openAITimestampGranularitiesJSON = "[]"

    @AppStorage(AppPreferenceKeys.sttGroqBaseURL) private var groqBaseURL = GroqAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.sttGroqModel) private var groqModel = "whisper-large-v3-turbo"
    @AppStorage(AppPreferenceKeys.sttGroqLanguage) private var groqLanguage = ""
    @AppStorage(AppPreferenceKeys.sttGroqPrompt) private var groqPrompt = ""
    @AppStorage(AppPreferenceKeys.sttGroqTranslateToEnglish) private var groqTranslateToEnglish = false
    @AppStorage(AppPreferenceKeys.sttGroqResponseFormat) private var groqResponseFormat = "json"
    @AppStorage(AppPreferenceKeys.sttGroqTemperature) private var groqTemperature = 0.0
    @AppStorage(AppPreferenceKeys.sttGroqTimestampGranularitiesJSON) private var groqTimestampGranularitiesJSON = "[]"

    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var provider: SpeechToTextProvider {
        SpeechToTextProvider(rawValue: providerRaw) ?? .groq
    }

    private var currentKeychainID: String {
        switch provider {
        case .openai:
            return OpenAIAudioClient.Constants.keychainID
        case .groq:
            return GroqAudioClient.Constants.keychainID
        }
    }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedAPIKey.isEmpty && !isSaving && !isTesting
    }

    var body: some View {
        Form {
            Section("Speech to Text") {
                Text("Adds a microphone button to the chat composer so you can dictate messages.")
                    .jinInfoCallout()
            }

            Section("Provider") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(SpeechToTextProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerRaw) { _, _ in
                    Task { await loadExistingKey() }
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }

                Toggle("Add recording as file", isOn: $addRecordingAsFile)
                    .help("Add recording as audio files for chat models that support audio input instead of transcribing.")
                    .disabled(true)

                Text("Audio attachment input isn’t supported in Jin yet. This option will be enabled in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

                Text("Stored in Keychain. Unsigned builds (e.g. `swift run`) may prompt repeatedly; running from Xcode (signed) is smoother.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Save") { saveKey() }
                        .disabled(!canSave)

                    Button("Test Connection") { testConnection() }
                        .disabled(trimmedAPIKey.isEmpty || isSaving || isTesting)

                    Button("Clear", role: .destructive) { clearKey() }
                        .disabled(isSaving || isTesting)

                    Spacer()

                    if isSaving || isTesting {
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

            providerSpecificSettings
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("Speech to Text")
        .task {
            await loadExistingKey()
        }
    }

    @ViewBuilder
    private var providerSpecificSettings: some View {
        switch provider {
        case .openai:
            Section("OpenAI") {
                TextField("API Base URL", text: $openAIBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Model", text: $openAIModel)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Toggle("Translate to English", isOn: $openAITranslateToEnglish)

                TextField("Language (optional)", text: $openAILanguage)
                    .font(.system(.body, design: .monospaced))

                TextField("Prompt (optional)", text: $openAIPrompt)

                Picker("Response Format", selection: $openAIResponseFormat) {
                    ForEach(Self.sttResponseFormats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Temperature")
                    Slider(value: $openAITemperature, in: 0.0...1.0, step: 0.05)
                    Text(openAITemperature.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                DisclosureGroup("Timestamps (verbose_json only)") {
                    Toggle("Segment timestamps", isOn: timestampBinding(provider: .openai, granularity: "segment"))
                    Toggle("Word timestamps", isOn: timestampBinding(provider: .openai, granularity: "word"))
                }
            }

        case .groq:
            Section("Groq") {
                TextField("API Base URL", text: $groqBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Model", text: $groqModel)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .help("Recommended: whisper-large-v3-turbo")

                Toggle("Translate to English", isOn: $groqTranslateToEnglish)

                TextField("Language (optional)", text: $groqLanguage)
                    .font(.system(.body, design: .monospaced))
                    .help("Only supported by whisper-large-v3.")

                TextField("Prompt (optional)", text: $groqPrompt)

                Picker("Response Format", selection: $groqResponseFormat) {
                    ForEach(Self.sttResponseFormats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Temperature")
                    Slider(value: $groqTemperature, in: 0.0...1.0, step: 0.05)
                    Text(groqTemperature.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                DisclosureGroup("Timestamps (verbose_json only)") {
                    Toggle("Segment timestamps", isOn: timestampBinding(provider: .groq, granularity: "segment"))
                    Toggle("Word timestamps", isOn: timestampBinding(provider: .groq, granularity: "word"))
                }
            }
        }
    }

    private func timestampBinding(provider: SpeechToTextProvider, granularity: String) -> Binding<Bool> {
        Binding(
            get: {
                let raw = provider == .openai ? openAITimestampGranularitiesJSON : groqTimestampGranularitiesJSON
                return Set(AppPreferences.decodeStringArrayJSON(raw)).contains(granularity)
            },
            set: { isOn in
                let raw = provider == .openai ? openAITimestampGranularitiesJSON : groqTimestampGranularitiesJSON
                var set = Set(AppPreferences.decodeStringArrayJSON(raw))
                if isOn {
                    set.insert(granularity)
                } else {
                    set.remove(granularity)
                }
                let updated = AppPreferences.encodeStringArrayJSON(Array(set).sorted())
                if provider == .openai {
                    openAITimestampGranularitiesJSON = updated
                } else {
                    groqTimestampGranularitiesJSON = updated
                }
            }
        )
    }

    private func loadExistingKey() async {
        let keychainManager = KeychainManager()
        let existing = (try? await keychainManager.getAPIKey(for: currentKeychainID)) ?? ""
        await MainActor.run {
            apiKey = existing
        }
    }

    private func saveKey() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isSaving = true

        Task {
            do {
                let keychainManager = KeychainManager()
                try await keychainManager.saveAPIKey(trimmedAPIKey, for: currentKeychainID)
                await MainActor.run {
                    isSaving = false
                    statusMessage = "Saved."
                    statusIsError = false
                }
                NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func clearKey() {
        statusMessage = nil
        statusIsError = false
        isSaving = true

        Task {
            do {
                let keychainManager = KeychainManager()
                try await keychainManager.deleteAPIKey(for: currentKeychainID)
                await MainActor.run {
                    apiKey = ""
                    isSaving = false
                    statusMessage = "Cleared."
                    statusIsError = false
                }
                NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func testConnection() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        Task {
            do {
                switch provider {
                case .openai:
                    let base = URL(string: openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? OpenAIAudioClient.Constants.defaultBaseURL
                    let client = OpenAIAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                case .groq:
                    let base = URL(string: groqBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? GroqAudioClient.Constants.defaultBaseURL
                    let client = GroqAudioClient(apiKey: trimmedAPIKey, baseURL: base)
                    try await client.validateAPIKey()
                }

                await MainActor.run {
                    isTesting = false
                    statusMessage = "Connection OK."
                    statusIsError = false
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private static let sttResponseFormats: [String] = [
        "json",
        "text",
        "verbose_json",
        "srt",
        "vtt"
    ]
}
