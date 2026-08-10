import SwiftUI

// MARK: - Provider-Specific Settings & Constants

extension SpeechToTextPluginSettingsView {

    @ViewBuilder
    var providerSpecificSettings: some View {
        if let provider {
            switch provider {
            case .openai:
                standardTranscriptionSettingsSection(
                    title: "OpenAI",
                    baseURL: $openAIBaseURL,
                    model: $openAIModel,
                    displayedModels: displayedOpenAIModels,
                    translateToEnglish: $openAITranslateToEnglish,
                    language: $openAILanguage,
                    prompt: $openAIPrompt,
                    responseFormat: $openAIResponseFormat,
                    temperature: $openAITemperature,
                    timestampProvider: .openai
                )

            case .openRouter:
                openRouterSettingsSection

            case .groq:
                standardTranscriptionSettingsSection(
                    title: "Groq",
                    baseURL: $groqBaseURL,
                    model: $groqModel,
                    displayedModels: displayedGroqModels,
                    translateToEnglish: $groqTranslateToEnglish,
                    language: $groqLanguage,
                    prompt: $groqPrompt,
                    responseFormat: $groqResponseFormat,
                    temperature: $groqTemperature,
                    timestampProvider: .groq
                )

            case .mistral:
                standardTranscriptionSettingsSection(
                    title: "Mistral",
                    baseURL: $mistralBaseURL,
                    model: $mistralModel,
                    displayedModels: displayedMistralModels,
                    language: $mistralLanguage,
                    prompt: $mistralPrompt,
                    responseFormat: $mistralResponseFormat,
                    temperature: $mistralTemperature,
                    timestampProvider: .mistral
                )

            case .elevenlabs:
                elevenLabsSettingsSection
            }
        } else {
            providerErrorSection
        }
    }

    var openRouterSettingsSection: some View {
        JinSettingsSection("OpenRouter") {
            JinSettingsTextFieldRow("API Base URL", text: $openRouterBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $openRouterModel) {
                ForEach(displayedOpenRouterModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            JinSettingsTextFieldRow(
                "Language",
                fieldTitle: "auto-detect",
                text: $openRouterLanguage,
                usesMonospacedFont: true
            )

            JinSettingsSliderValueRow(
                title: "Temperature",
                value: $openRouterTemperature,
                range: 0.0...1.0,
                step: 0.05
            )
        }
    }

    var availableOpenRouterModels: [SpeechProviderModelChoice] {
        openRouterModels.isEmpty
            ? SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .openRouter)
            : openRouterModels
    }

    var displayedOpenRouterModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableOpenRouterModels, selectedModelID: openRouterModel)
    }

    var elevenLabsSettingsSection: some View {
        JinSettingsSection("ElevenLabs") {
            JinSettingsTextFieldRow("API Base URL", text: $elevenLabsBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $elevenLabsModel) {
                ForEach(displayedElevenLabsModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            JinSettingsTextFieldRow(
                "Language Code",
                fieldTitle: "auto-detect",
                text: $elevenLabsLanguageCode,
                usesMonospacedFont: true
            )
            .help("ISO-639-1 or ISO-639-3 code. Leave empty for auto-detection.")

            JinSettingsToggleRow("Tag audio events", isOn: $elevenLabsTagAudioEvents)
                .help("Tag events like (laughter), (footsteps) in the transcription.")

            JinSettingsToggleRow("No verbatim", isOn: $elevenLabsNoVerbatim)
                .help("Remove filler words, false starts and non-speech sounds. Scribe v2 only.")
                .disabled(elevenLabsModel != "scribe_v2")

            JinSettingsToggleRow("Diarize", isOn: $elevenLabsDiarize)
                .help("Annotate which speaker is talking.")

            if elevenLabsDiarize {
                Stepper("Max speakers: \(elevenLabsNumSpeakers)", value: $elevenLabsNumSpeakers, in: 1...32)
            }

            JinSettingsPickerRow("Timestamps", selection: $elevenLabsTimestampsGranularity) {
                Text("None").tag("none")
                Text("Word").tag("word")
                Text("Character").tag("character")
            }

            JinSettingsPickerRow(
                "File Format",
                supportingText: "Use PCM for lower latency when recording is already 16-bit 16kHz mono.",
                selection: $elevenLabsFileFormat
            ) {
                Text("Auto-detect").tag("other")
                Text("PCM 16-bit 16kHz").tag("pcm_s16le_16")
            }

            JinSettingsSliderValueRow(
                title: "Temperature",
                value: $elevenLabsTemperature,
                range: 0.0...2.0,
                step: 0.05
            )
        }
    }

    var providerErrorSection: some View {
        JinSettingsSection("Unknown Provider", style: .plain) {
            JinSettingsErrorText(text: providerErrorMessage(for: providerRaw))
        }
    }

    @ViewBuilder
    func standardTranscriptionSettingsSection(
        title: String,
        baseURL: Binding<String>,
        model: Binding<String>,
        displayedModels: [SpeechProviderModelChoice],
        translateToEnglish: Binding<Bool>? = nil,
        language: Binding<String>,
        prompt: Binding<String>,
        responseFormat: Binding<String>,
        temperature: Binding<Double>,
        timestampProvider: SpeechToTextProvider
    ) -> some View {
        JinSettingsSection(title) {
            JinSettingsTextFieldRow("API Base URL", text: baseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: model) {
                ForEach(displayedModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            if let translateToEnglish {
                JinSettingsToggleRow("Translate to English", isOn: translateToEnglish)
            }

            JinSettingsTextFieldRow(
                "Language",
                fieldTitle: "auto-detect",
                text: language,
                usesMonospacedFont: true
            )

            JinSettingsTextFieldRow(
                "Prompt",
                text: prompt
            )

            JinSettingsPickerRow("Response Format", selection: responseFormat) {
                ForEach(Self.sttResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }

            JinSettingsSliderValueRow(
                title: "Temperature",
                value: temperature,
                range: 0.0...1.0,
                step: 0.05
            )

            timestampGranularityDisclosure(provider: timestampProvider)
        }
    }

    func timestampGranularityDisclosure(provider: SpeechToTextProvider) -> some View {
        DisclosureGroup("Timestamps (verbose_json only)") {
            Toggle("Segment timestamps", isOn: timestampBinding(provider: provider, granularity: "segment"))
            Toggle("Word timestamps", isOn: timestampBinding(provider: provider, granularity: "word"))
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
        case .openRouter, .elevenlabs:
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
        case .openRouter, .elevenlabs:
            break
        }
    }

    var availableOpenAIModels: [SpeechProviderModelChoice] {
        openAIModels.isEmpty
            ? SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .openai)
            : openAIModels
    }

    var displayedOpenAIModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableOpenAIModels, selectedModelID: openAIModel)
    }

    var availableGroqModels: [SpeechProviderModelChoice] {
        groqModels.isEmpty
            ? SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .groq)
            : groqModels
    }

    var displayedGroqModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableGroqModels, selectedModelID: groqModel)
    }

    var availableMistralModels: [SpeechProviderModelChoice] {
        mistralModels.isEmpty
            ? SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .mistral)
            : mistralModels
    }

    var displayedMistralModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableMistralModels, selectedModelID: mistralModel)
    }

    var availableElevenLabsModels: [SpeechProviderModelChoice] {
        elevenLabsModels.isEmpty
            ? SpeechProviderModelCatalog.defaultSpeechToTextChoices(for: .elevenlabs)
            : elevenLabsModels
    }

    var displayedElevenLabsModels: [SpeechProviderModelChoice] {
        SpeechProviderModelCatalog.presentingChoices(availableElevenLabsModels, selectedModelID: elevenLabsModel)
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
