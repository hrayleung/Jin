import SwiftUI

// MARK: - Provider-Specific Settings & Constants

extension SpeechToTextPluginSettingsView {

    @ViewBuilder
    var providerSpecificSettings: some View {
        if let provider {
            switch provider {
            case .openai:
                Section("OpenAI") {
                    TextField("API Base URL", text: $openAIBaseURL)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    if !displayedOpenAIModels.isEmpty {
                        Picker("Model", selection: $openAIModel) {
                            ForEach(displayedOpenAIModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("Model", text: $openAIModel)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

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

                    if !displayedGroqModels.isEmpty {
                        Picker("Model", selection: $groqModel) {
                            ForEach(displayedGroqModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("Model", text: $groqModel)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Translate to English", isOn: $groqTranslateToEnglish)

                    TextField("Language (optional)", text: $groqLanguage)
                        .font(.system(.body, design: .monospaced))

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

            case .mistral:
                Section("Mistral") {
                    TextField("API Base URL", text: $mistralBaseURL)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    if !displayedMistralModels.isEmpty {
                        Picker("Model", selection: $mistralModel) {
                            ForEach(displayedMistralModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("Model", text: $mistralModel)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Language (optional)", text: $mistralLanguage)
                        .font(.system(.body, design: .monospaced))

                    TextField("Prompt (optional)", text: $mistralPrompt)

                    Picker("Response Format", selection: $mistralResponseFormat) {
                        ForEach(Self.sttResponseFormats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("Temperature")
                        Slider(value: $mistralTemperature, in: 0.0...1.0, step: 0.05)
                        Text(mistralTemperature.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }

                    DisclosureGroup("Timestamps (verbose_json only)") {
                        Toggle("Segment timestamps", isOn: timestampBinding(provider: .mistral, granularity: "segment"))
                        Toggle("Word timestamps", isOn: timestampBinding(provider: .mistral, granularity: "word"))
                    }
                }

            case .whisperKit:
                WhisperKitSpeechToTextSettingsSection(
                    modelSelection: $whisperKitModel,
                    language: $whisperKitLanguage,
                    translateToEnglish: $whisperKitTranslateToEnglish
                )

            case .elevenlabs:
                Section("ElevenLabs") {
                    TextField("API Base URL", text: $elevenLabsBaseURL)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    if !displayedElevenLabsModels.isEmpty {
                        Picker("Model", selection: $elevenLabsModel) {
                            ForEach(displayedElevenLabsModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        TextField("Model", text: $elevenLabsModel)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Language Code (optional)", text: $elevenLabsLanguageCode)
                        .font(.system(.body, design: .monospaced))
                        .help("ISO-639-1 or ISO-639-3 code. Leave empty for auto-detection.")

                    Toggle("Tag audio events", isOn: $elevenLabsTagAudioEvents)
                        .help("Tag events like (laughter), (footsteps) in the transcription.")

                    Toggle("No verbatim", isOn: $elevenLabsNoVerbatim)
                        .help("Remove filler words, false starts and non-speech sounds. Scribe v2 only.")
                        .disabled(elevenLabsModel != "scribe_v2")

                    Toggle("Diarize", isOn: $elevenLabsDiarize)
                        .help("Annotate which speaker is talking.")

                    if elevenLabsDiarize {
                        Stepper("Max speakers: \(elevenLabsNumSpeakers)", value: $elevenLabsNumSpeakers, in: 1...32)
                    }

                    Picker("Timestamps", selection: $elevenLabsTimestampsGranularity) {
                        Text("None").tag("none")
                        Text("Word").tag("word")
                        Text("Character").tag("character")
                    }
                    .pickerStyle(.menu)

                    Picker("File Format", selection: $elevenLabsFileFormat) {
                        Text("Auto-detect").tag("other")
                        Text("PCM 16-bit 16kHz").tag("pcm_s16le_16")
                    }
                    .pickerStyle(.menu)
                    .help("Use PCM for lower latency when recording is already 16-bit 16kHz mono.")

                    HStack {
                        Text("Temperature")
                        Slider(value: $elevenLabsTemperature, in: 0.0...2.0, step: 0.05)
                        Text(elevenLabsTemperature.formatted(.number.precision(.fractionLength(2))))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        } else {
            Section("Provider Error") {
                Text(providerErrorMessage(for: providerRaw))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    func timestampBinding(provider: SpeechToTextProvider, granularity: String) -> Binding<Bool> {
        Binding(
            get: {
                let raw = timestampGranularitiesJSON(for: provider)
                return Set(AppPreferences.decodeStringArrayJSON(raw)).contains(granularity)
            },
            set: { isOn in
                let raw = timestampGranularitiesJSON(for: provider)
                var set = Set(AppPreferences.decodeStringArrayJSON(raw))
                if isOn {
                    set.insert(granularity)
                } else {
                    set.remove(granularity)
                }
                let updated = AppPreferences.encodeStringArrayJSON(Array(set).sorted())
                setTimestampGranularitiesJSON(updated, for: provider)
            }
        )
    }

    func timestampGranularitiesJSON(for provider: SpeechToTextProvider) -> String {
        switch provider {
        case .openai:
            return openAITimestampGranularitiesJSON
        case .groq:
            return groqTimestampGranularitiesJSON
        case .mistral:
            return mistralTimestampGranularitiesJSON
        case .elevenlabs, .whisperKit:
            return "[]"
        }
    }

    func setTimestampGranularitiesJSON(_ value: String, for provider: SpeechToTextProvider) {
        switch provider {
        case .openai:
            openAITimestampGranularitiesJSON = value
        case .groq:
            groqTimestampGranularitiesJSON = value
        case .mistral:
            mistralTimestampGranularitiesJSON = value
        case .elevenlabs, .whisperKit:
            break
        }
    }

    var displayedOpenAIModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(openAIModels, selectedModelID: openAIModel)
    }

    var displayedGroqModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(groqModels, selectedModelID: groqModel)
    }

    var displayedMistralModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(mistralModels, selectedModelID: mistralModel)
    }

    var displayedElevenLabsModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(elevenLabsModels, selectedModelID: elevenLabsModel)
    }

    // MARK: - Static Constants

    static let sttResponseFormats: [String] = [
        "json",
        "text",
        "verbose_json",
        "srt",
        "vtt"
    ]
}
