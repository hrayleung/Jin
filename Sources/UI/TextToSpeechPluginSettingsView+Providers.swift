import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Provider-Specific Settings & Constants

extension TextToSpeechPluginSettingsView {

    @ViewBuilder
    var providerSpecificSettings: some View {
        if let provider {
            switch provider {
            case .openai:
                JinSettingsSection("OpenAI") {
                    JinSettingsControlRow("API Base URL") {
                        TextField("API Base URL", text: $openAIBaseURL)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    JinSettingsControlRow("Model") {
                        Picker("Model", selection: $openAIModel) {
                            ForEach(displayedOpenAIModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    JinSettingsControlRow("Voice") {
                        Picker("Voice", selection: $openAIVoice) {
                            ForEach(Self.openAIVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    JinSettingsControlRow("Format") {
                        Picker("Format", selection: $openAIResponseFormat) {
                            ForEach(Self.openAIResponseFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    JinSettingsControlRow("Speed") {
                        HStack {
                            Slider(value: $openAISpeed, in: 0.25...4.0, step: 0.05)
                            Text(openAISpeed.formatted(.number.precision(.fractionLength(2))))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }

                    JinSettingsControlRow("Instructions", supportingText: "Optional.") {
                        TextField("Instructions (optional)", text: $openAIInstructions)
                            .textFieldStyle(.roundedBorder)
                    }
                }

            case .groq:
                JinSettingsSection("Groq") {
                    JinSettingsControlRow("API Base URL") {
                        TextField("API Base URL", text: $groqBaseURL)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    JinSettingsControlRow("Model") {
                        Picker("Model", selection: $groqModel) {
                            ForEach(displayedGroqModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .help("Orpheus models: canopylabs/orpheus-v1-english, canopylabs/orpheus-arabic-saudi")
                    .onChange(of: groqModel) { _, _ in
                        normalizeGroqVoiceIfNeeded()
                    }

                    JinSettingsControlRow("Voice") {
                        Picker("Voice", selection: $groqVoice) {
                            ForEach(groqVoiceChoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        normalizeGroqVoiceIfNeeded()
                    }

                    JinSettingsControlRow("Format") {
                        Picker("Format", selection: $groqResponseFormat) {
                            Text("wav").tag("wav")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

            case .xiaomiMiMo:
                JinSettingsSection("Xiaomi MiMo") {
                    JinSettingsControlRow("API Base URL") {
                        TextField("API Base URL", text: $miMoBaseURL)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    JinSettingsControlRow("Model") {
                        Picker("Model", selection: $miMoModel) {
                            ForEach(displayedMiMoModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: miMoModel) { _, _ in
                        normalizeMiMoVoiceIfNeeded()
                    }

                    if miMoModel != "mimo-v2.5-tts-voicedesign" && miMoModel != "mimo-v2.5-tts-voiceclone" {
                        JinSettingsControlRow("Voice") {
                            Picker("Voice", selection: $miMoVoice) {
                                ForEach(miMoVoiceChoices, id: \.self) { voice in
                                    Text(voice).tag(voice)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onAppear {
                            normalizeMiMoVoiceIfNeeded()
                        }
                    }

                    if miMoModel == "mimo-v2.5-tts-voiceclone" {
                        JinSettingsControlRow("Voice Sample", supportingText: "Required for VoiceClone. Use an mp3 or wav sample.") {
                            HStack {
                                TextField("Voice sample path", text: $miMoVoiceCloneSamplePath)
                                    .font(.system(.body, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)

                                Button("Choose…") {
                                    chooseMiMoVoiceCloneSample()
                                }
                            }
                        }
                    }

                    JinSettingsControlRow("Format") {
                        Picker("Format", selection: $miMoResponseFormat) {
                            ForEach(Self.miMoResponseFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    JinSettingsControlRow(
                        miMoModel == "mimo-v2.5-tts-voicedesign" ? "Voice Design" : "Style",
                        supportingText: miMoModel == "mimo-v2.5-tts-voicedesign" ? "Required." : "Optional."
                    ) {
                        TextField("Describe voice or speaking style", text: $miMoStyleInstruction)
                            .textFieldStyle(.roundedBorder)
                    }
                }

            case .elevenlabs:
                JinSettingsSection("ElevenLabs") {
                    JinSettingsControlRow("API Base URL") {
                        TextField("API Base URL", text: $elevenLabsBaseURL)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    JinSettingsControlRow("Model") {
                        Picker("Model", selection: $elevenLabsModelID) {
                            ForEach(displayedElevenLabsModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !elevenLabsVoices.isEmpty {
                        JinSettingsControlRow("Voice") {
                            HStack {
                                Picker("Voice", selection: $elevenLabsVoiceID) {
                                    ForEach(elevenLabsVoices) { voice in
                                        Text(voice.name).tag(voice.voiceId)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        }
                    } else {
                        Text("No voices loaded. Enter your API key and click \u{201C}Test Connection\u{201D} to fetch voices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    JinSettingsControlRow("Output Format") {
                        Picker("Output Format", selection: $elevenLabsOutputFormat) {
                            ForEach(Self.elevenLabsOutputFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Stepper("Optimize latency: \(elevenLabsOptimizeStreamingLatency)", value: $elevenLabsOptimizeStreamingLatency, in: 0...4)

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

            case .whisperKit:
                TTSKitTextToSpeechSettingsSection(
                    modelSelection: $ttsKitModel,
                    voiceSelection: $ttsKitVoice,
                    languageSelection: $ttsKitLanguage,
                    styleInstruction: $ttsKitStyleInstruction,
                    playbackModeRaw: $ttsKitPlaybackMode
                )
            }
        } else {
            JinSettingsSection("Provider Error") {
                Text(providerErrorMessage(for: providerRaw))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    func sliderRow(title: String, value: Binding<Double>) -> some View {
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

    var selectedElevenLabsVoicePreviewURL: URL? {
        guard provider == .elevenlabs else { return nil }
        guard let voice = elevenLabsVoices.first(where: { $0.voiceId == elevenLabsVoiceID }) else { return nil }
        guard let str = voice.previewUrl, let url = URL(string: str) else { return nil }
        return url
    }

    var availableOpenAIModels: [SpeechProviderModelChoice] {
        openAIModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .openai)
            : openAIModels
    }

    var displayedOpenAIModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableOpenAIModels, selectedModelID: openAIModel)
    }

    var availableGroqModels: [SpeechProviderModelChoice] {
        groqModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .groq)
            : groqModels
    }

    var displayedGroqModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableGroqModels, selectedModelID: groqModel)
    }

    var availableMiMoModels: [SpeechProviderModelChoice] {
        miMoModels.isEmpty
            ? SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .xiaomiMiMo)
            : miMoModels
    }

    var displayedMiMoModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableMiMoModels, selectedModelID: miMoModel)
    }

    var availableElevenLabsModels: [SpeechProviderModelChoice] {
        if !elevenLabsModels.isEmpty {
            return elevenLabsModels.map { model in
                SpeechProviderModelChoice(id: model.modelId, name: model.name)
            }
        }
        return SpeechProviderModelCatalog.defaultTextToSpeechChoices(for: .elevenlabs)
    }

    var displayedElevenLabsModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(
            availableElevenLabsModels,
            selectedModelID: elevenLabsModelID
        )
    }

    // MARK: - Groq Voice Helpers

    var groqVoiceChoices: [String] {
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

    func normalizeGroqVoiceIfNeeded() {
        let choices = groqVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(groqVoice) {
            groqVoice = choices[0]
        }
    }

    var miMoVoiceChoices: [String] {
        let lower = miMoModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "mimo-v2-tts" {
            return Self.miMoV2Voices
        }
        return Self.miMoV25Voices
    }

    func normalizeMiMoVoiceIfNeeded() {
        let choices = miMoVoiceChoices
        guard !choices.isEmpty else { return }
        if !choices.contains(miMoVoice) {
            miMoVoice = choices[0]
        }
    }

    func chooseMiMoVoiceCloneSample() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "wav")
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            miMoVoiceCloneSamplePath = url.path
        }
        #endif
    }

    // MARK: - Static Constants

    static let openAIVoices: [String] = [
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

    static let openAIResponseFormats: [String] = [
        "mp3",
        "wav",
        "aac",
        "flac",
        "pcm"
    ]

    static let groqOrpheusEnglishVoices: [String] = [
        "autumn",
        "diana",
        "hannah",
        "austin",
        "daniel",
        "troy"
    ]

    static let groqOrpheusArabicVoices: [String] = [
        "fahad",
        "sultan",
        "lulwa",
        "noura"
    ]

    static let miMoV25Voices: [String] = [
        "mimo_default",
        "冰糖",
        "茉莉",
        "苏打",
        "白桦",
        "Mia",
        "Chloe",
        "Milo",
        "Dean"
    ]

    static let miMoV2Voices: [String] = [
        "mimo_default",
        "default_en",
        "default_zh"
    ]

    static let miMoResponseFormats: [String] = [
        "wav",
        "mp3",
        "pcm",
        "pcm16"
    ]

    static let elevenLabsOutputFormats: [String] = [
        "mp3_44100_128",
        "mp3_44100_192",
        "pcm_16000",
        "pcm_22050",
        "pcm_24000",
        "pcm_44100"
    ]
}
