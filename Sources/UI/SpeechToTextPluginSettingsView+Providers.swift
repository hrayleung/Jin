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

                    TextField("Model", text: $mistralModel)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

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
        case .whisperKit:
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
        case .whisperKit:
            break
        }
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
