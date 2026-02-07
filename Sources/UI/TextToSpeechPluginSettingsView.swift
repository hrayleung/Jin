import SwiftUI
import AVFoundation

struct TextToSpeechPluginSettingsView: View {
    @AppStorage(AppPreferenceKeys.ttsProvider) private var providerRaw = TextToSpeechProvider.openai.rawValue

    @AppStorage(AppPreferenceKeys.ttsOpenAIBaseURL) private var openAIBaseURL = OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsOpenAIModel) private var openAIModel = "gpt-4o-mini-tts"
    @AppStorage(AppPreferenceKeys.ttsOpenAIVoice) private var openAIVoice = "alloy"
    @AppStorage(AppPreferenceKeys.ttsOpenAIResponseFormat) private var openAIResponseFormat = "mp3"
    @AppStorage(AppPreferenceKeys.ttsOpenAISpeed) private var openAISpeed = 1.0
    @AppStorage(AppPreferenceKeys.ttsOpenAIInstructions) private var openAIInstructions = ""

    @AppStorage(AppPreferenceKeys.ttsGroqBaseURL) private var groqBaseURL = GroqAudioClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsGroqModel) private var groqModel = "canopylabs/orpheus-v1-english"
    @AppStorage(AppPreferenceKeys.ttsGroqVoice) private var groqVoice = "troy"
    @AppStorage(AppPreferenceKeys.ttsGroqResponseFormat) private var groqResponseFormat = "wav"

    @AppStorage(AppPreferenceKeys.ttsElevenLabsBaseURL) private var elevenLabsBaseURL = ElevenLabsTTSClient.Constants.defaultBaseURL.absoluteString
    @AppStorage(AppPreferenceKeys.ttsElevenLabsModelID) private var elevenLabsModelID = "eleven_multilingual_v2"
    @AppStorage(AppPreferenceKeys.ttsElevenLabsVoiceID) private var elevenLabsVoiceID = ""
    @AppStorage(AppPreferenceKeys.ttsElevenLabsOutputFormat) private var elevenLabsOutputFormat = "mp3_44100_128"
    @AppStorage(AppPreferenceKeys.ttsElevenLabsOptimizeStreamingLatency) private var elevenLabsOptimizeStreamingLatency = 0
    @AppStorage(AppPreferenceKeys.ttsElevenLabsEnableLogging) private var elevenLabsEnableLogging = true
    @AppStorage(AppPreferenceKeys.ttsElevenLabsStability) private var elevenLabsStability = 0.5
    @AppStorage(AppPreferenceKeys.ttsElevenLabsSimilarityBoost) private var elevenLabsSimilarityBoost = 0.75
    @AppStorage(AppPreferenceKeys.ttsElevenLabsStyle) private var elevenLabsStyle = 0.0
    @AppStorage(AppPreferenceKeys.ttsElevenLabsUseSpeakerBoost) private var elevenLabsUseSpeakerBoost = true

    @State private var apiKey = ""
    @State private var isKeyVisible = false
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    @State private var elevenLabsVoices: [ElevenLabsTTSClient.Voice] = []
    @State private var isLoadingVoices = false
    @State private var voicePreviewPlayer: AVAudioPlayer?
    @State private var isPlayingVoicePreview = false

    private var provider: TextToSpeechProvider {
        TextToSpeechProvider(rawValue: providerRaw) ?? .openai
    }

    private var currentKeychainID: String {
        switch provider {
        case .elevenlabs:
            return ElevenLabsTTSClient.Constants.keychainID
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
            Section("Text to Speech") {
                Text("Adds a speaker button to assistant messages so you can play responses aloud.")
                    .jinInfoCallout()
            }

            Section("Provider") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(TextToSpeechProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: providerRaw) { _, _ in
                    Task { await loadExistingKeyAndMaybeVoices() }
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }
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

                    if isSaving || isTesting || isLoadingVoices {
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
        .navigationTitle("Text to Speech")
        .task {
            await loadExistingKeyAndMaybeVoices()
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

                Picker("Voice", selection: $openAIVoice) {
                    ForEach(Self.openAIVoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)

                Picker("Format", selection: $openAIResponseFormat) {
                    ForEach(Self.openAIResponseFormats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Speed")
                    Slider(value: $openAISpeed, in: 0.25...4.0, step: 0.05)
                    Text(openAISpeed.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .trailing)
                }

                TextField("Instructions (optional)", text: $openAIInstructions)
            }

        case .groq:
            Section("Groq") {
                TextField("API Base URL", text: $groqBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Model", text: $groqModel)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .help("Orpheus models: canopylabs/orpheus-v1-english, canopylabs/orpheus-arabic-saudi")
                    .onChange(of: groqModel) { _, _ in
                        normalizeGroqVoiceIfNeeded()
                    }

                Picker("Voice", selection: $groqVoice) {
                    ForEach(groqVoiceChoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    normalizeGroqVoiceIfNeeded()
                }

                Picker("Format", selection: $groqResponseFormat) {
                    Text("wav").tag("wav")
                }
                .pickerStyle(.menu)

                Text("Note: Orpheus limits each request to 200 characters. Jin will chunk long messages automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Tip: Orpheus supports vocal directions like `[cheerful]` or `[sighs]` inline in your text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .elevenlabs:
            Section("ElevenLabs") {
                TextField("API Base URL", text: $elevenLabsBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Model", text: $elevenLabsModelID)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                if !elevenLabsVoices.isEmpty {
                    HStack {
                        Picker("Voice", selection: $elevenLabsVoiceID) {
                            ForEach(elevenLabsVoices) { voice in
                                Text(voice.name).tag(voice.voiceId)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: elevenLabsVoiceID) { _, _ in
                            NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                        }

                        Button {
                            Task { await playSelectedVoicePreview() }
                        } label: {
                            Image(systemName: isPlayingVoicePreview ? "stop.circle" : "play.circle")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Play voice preview")
                        .disabled(selectedElevenLabsVoicePreviewURL == nil)
                    }
                } else {
                    Text("No voices loaded. Save your API key and click “Test Connection” to fetch voices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Output Format", selection: $elevenLabsOutputFormat) {
                    ForEach(Self.elevenLabsOutputFormats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
                .pickerStyle(.menu)

                Stepper("Optimize latency: \(elevenLabsOptimizeStreamingLatency)", value: $elevenLabsOptimizeStreamingLatency, in: 0...4)
                    .help("Higher values reduce latency but may lower audio quality.")

                Toggle("Enable logging", isOn: $elevenLabsEnableLogging)

                DisclosureGroup("Voice Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        sliderRow(title: "Stability", value: $elevenLabsStability)
                        sliderRow(title: "Similarity", value: $elevenLabsSimilarityBoost)
                        sliderRow(title: "Style", value: $elevenLabsStyle)
                        Toggle("Use speaker boost", isOn: $elevenLabsUseSpeakerBoost)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 88, alignment: .leading)
            Slider(value: value, in: 0.0...1.0, step: 0.01)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var selectedElevenLabsVoicePreviewURL: URL? {
        guard provider == .elevenlabs else { return nil }
        guard let voice = elevenLabsVoices.first(where: { $0.voiceId == elevenLabsVoiceID }) else { return nil }
        guard let str = voice.previewUrl, let url = URL(string: str) else { return nil }
        return url
    }

    private func loadExistingKeyAndMaybeVoices() async {
        await loadExistingKey()
        if provider == .elevenlabs, !trimmedAPIKey.isEmpty {
            await loadElevenLabsVoices()
        } else {
            await MainActor.run {
                elevenLabsVoices = []
                isPlayingVoicePreview = false
                voicePreviewPlayer?.stop()
                voicePreviewPlayer = nil
            }
        }
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
                await loadExistingKeyAndMaybeVoices()
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
                    elevenLabsVoices = []
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
                case .elevenlabs:
                    let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ElevenLabsTTSClient.Constants.defaultBaseURL
                    let client = ElevenLabsTTSClient(apiKey: trimmedAPIKey, baseURL: base)
                    let voices = try await client.listVoices()

                    let selectedVoice = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let voiceIdToTest = !selectedVoice.isEmpty ? selectedVoice : (voices.first?.voiceId ?? "")
                    guard !voiceIdToTest.isEmpty else {
                        throw SpeechExtensionError.missingElevenLabsVoice
                    }

                    let voiceSettings = ElevenLabsTTSClient.VoiceSettings(
                        stability: elevenLabsStability,
                        similarityBoost: elevenLabsSimilarityBoost,
                        style: elevenLabsStyle,
                        useSpeakerBoost: elevenLabsUseSpeakerBoost
                    )

                    // Validate that this key can actually synthesize audio (keys may be scope-restricted per endpoint).
                    _ = try await client.createSpeech(
                        text: "Hello from Jin.",
                        voiceId: voiceIdToTest,
                        modelId: elevenLabsModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : elevenLabsModelID,
                        outputFormat: elevenLabsOutputFormat,
                        optimizeStreamingLatency: elevenLabsOptimizeStreamingLatency,
                        enableLogging: elevenLabsEnableLogging,
                        voiceSettings: voiceSettings
                    )
                }

                await MainActor.run {
                    isTesting = false
                    statusMessage = "Connection OK."
                    statusIsError = false
                }

                if provider == .elevenlabs {
                    await loadElevenLabsVoices()
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    if let llmError = error as? LLMError, case .authenticationFailed = llmError {
                        statusMessage = "\(llmError.localizedDescription)\n\nIf your ElevenLabs key uses endpoint scopes, enable access to /v1/text-to-speech."
                    } else {
                        statusMessage = error.localizedDescription
                    }
                    statusIsError = true
                }
            }
        }
    }

    private func loadElevenLabsVoices() async {
        guard provider == .elevenlabs else { return }
        guard !trimmedAPIKey.isEmpty else { return }

        await MainActor.run {
            isLoadingVoices = true
        }

        do {
            let base = URL(string: elevenLabsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ElevenLabsTTSClient.Constants.defaultBaseURL
            let client = ElevenLabsTTSClient(apiKey: trimmedAPIKey, baseURL: base)
            let voices = try await client.listVoices()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await MainActor.run {
                elevenLabsVoices = voices
                if elevenLabsVoiceID.isEmpty {
                    elevenLabsVoiceID = voices.first?.voiceId ?? ""
                } else if !voices.contains(where: { $0.voiceId == elevenLabsVoiceID }) {
                    elevenLabsVoiceID = voices.first?.voiceId ?? ""
                }
                isLoadingVoices = false
            }
        } catch {
            await MainActor.run {
                elevenLabsVoices = []
                isLoadingVoices = false
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func playSelectedVoicePreview() async {
        guard let url = selectedElevenLabsVoicePreviewURL else { return }

        if isPlayingVoicePreview {
            await MainActor.run {
                voicePreviewPlayer?.stop()
                voicePreviewPlayer = nil
                isPlayingVoicePreview = false
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            await MainActor.run {
                voicePreviewPlayer = player
                isPlayingVoicePreview = true
            }
            player.play()

            // Poll completion state (AVAudioPlayer delegate requires NSObject conformance).
            Task { @MainActor in
                while player.isPlaying {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if voicePreviewPlayer === player {
                    voicePreviewPlayer = nil
                    isPlayingVoicePreview = false
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = error.localizedDescription
                statusIsError = true
                isPlayingVoicePreview = false
            }
        }
    }

    private static let openAIVoices: [String] = [
        "alloy",
        "ash",
        "ballad",
        "cedar",
        "coral",
        "echo",
        "fable",
        "marin",
        "nova",
        "onyx",
        "sage",
        "shimmer",
        "verse"
    ]

    private static let openAIResponseFormats: [String] = [
        "mp3",
        "wav",
        "aac",
        "flac",
        "pcm"
    ]

    private var groqVoiceChoices: [String] {
        let lower = groqModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("orpheus-arabic-saudi") {
            return Self.groqOrpheusArabicVoices
        }
        if lower.contains("orpheus-v1-english") || lower.contains("orpheus") {
            return Self.groqOrpheusEnglishVoices
        }
        return (Self.groqOrpheusEnglishVoices + Self.groqOrpheusArabicVoices)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalizeGroqVoiceIfNeeded() {
        let choices = groqVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(groqVoice) {
            groqVoice = choices[0]
        }
    }

    private static let groqOrpheusEnglishVoices: [String] = [
        "autumn",
        "diana",
        "hannah",
        "austin",
        "daniel",
        "troy"
    ]

    private static let groqOrpheusArabicVoices: [String] = [
        "fahad",
        "sultan",
        "lulwa",
        "noura"
    ]

    private static let elevenLabsOutputFormats: [String] = [
        "mp3_44100_128",
        "mp3_44100_192",
        "pcm_16000",
        "pcm_22050",
        "pcm_24000",
        "pcm_44100"
    ]
}
