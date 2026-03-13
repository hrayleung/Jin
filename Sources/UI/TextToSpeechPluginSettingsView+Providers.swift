import SwiftUI

// MARK: - Provider-Specific Settings & Constants

extension TextToSpeechPluginSettingsView {

    @ViewBuilder
    var providerSpecificSettings: some View {
        if let provider {
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
                        Text("No voices loaded. Enter your API key and click \u{201C}Test Connection\u{201D} to fetch voices.")
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
            Section("Provider Error") {
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

    static let elevenLabsOutputFormats: [String] = [
        "mp3_44100_128",
        "mp3_44100_192",
        "pcm_16000",
        "pcm_22050",
        "pcm_24000",
        "pcm_44100"
    ]
}
