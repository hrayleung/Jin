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
                    capabilities: capabilities(for: .openai, model: openAIModel),
                    baseURL: $openAIBaseURL,
                    model: $openAIModel,
                    displayedModels: displayedOpenAIModels,
                    translateToEnglish: $openAITranslateToEnglish,
                    language: $openAILanguage,
                    keywords: $openAIKeywords,
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
                    capabilities: capabilities(for: .groq, model: groqModel),
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
                    capabilities: capabilities(for: .mistral, model: mistralModel),
                    baseURL: $mistralBaseURL,
                    model: $mistralModel,
                    displayedModels: displayedMistralModels,
                    language: $mistralLanguage,
                    prompt: $mistralPrompt,
                    responseFormat: $mistralResponseFormat,
                    temperature: $mistralTemperature,
                    timestampProvider: .mistral,
                    diarize: $mistralDiarize
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
            JinSettingsTextFieldRow("Base URL", text: $openRouterBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $openRouterModel) {
                ForEach(displayedOpenRouterModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            JinSettingsTextFieldRow(
                "Language",
                prompt: "auto-detect",
                text: $openRouterLanguage,
                usesMonospacedFont: true
            )

            // OpenRouter rejects text/srt/vtt on the transcription endpoint.
            JinSettingsPickerRow("Response Format", selection: $openRouterResponseFormat) {
                ForEach(capabilities(for: .openRouter, model: openRouterModel).responseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .onAppear {
                normalizeResponseFormat(
                    $openRouterResponseFormat,
                    provider: .openRouter,
                    model: openRouterModel
                )
            }
            .onChange(of: openRouterModel) { _, newModel in
                normalizeResponseFormat(
                    $openRouterResponseFormat,
                    provider: .openRouter,
                    model: newModel
                )
            }

            JinSettingsSliderValueRow(
                title: "Temperature",
                value: $openRouterTemperature,
                range: 0.0...1.0,
                step: 0.05
            )

            timestampGranularityDisclosure(provider: .openRouter)
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
            JinSettingsTextFieldRow("Base URL", text: $elevenLabsBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $elevenLabsModel) {
                ForEach(displayedElevenLabsModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            JinSettingsTextFieldRow(
                "Language Code",
                prompt: "auto-detect",
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

            // The API enum is word | character; "None" simply omits the parameter.
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
        JinSettingsSection("Unknown Provider") {
            JinSettingsErrorText(text: providerErrorMessage(for: providerRaw))
        }
    }

    func capabilities(
        for provider: SpeechToTextProvider,
        model: String
    ) -> SpeechTranscriptionCapabilities {
        SpeechModelCapabilityRegistry.transcriptionCapabilities(provider: provider, modelID: model)
    }

    /// Renders only the controls the selected model actually accepts. The generations diverge
    /// enough that offering the union guarantees a 400 — `gpt-transcribe` takes `languages[]`
    /// and rejects timestamps, `whisper-1` is the only model that still emits subtitles.
    @ViewBuilder
    func standardTranscriptionSettingsSection(
        title: String,
        capabilities: SpeechTranscriptionCapabilities,
        baseURL: Binding<String>,
        model: Binding<String>,
        displayedModels: [SpeechProviderModelChoice],
        translateToEnglish: Binding<Bool>? = nil,
        language: Binding<String>,
        keywords: Binding<String>? = nil,
        prompt: Binding<String>,
        responseFormat: Binding<String>,
        temperature: Binding<Double>,
        timestampProvider: SpeechToTextProvider,
        diarize: Binding<Bool>? = nil
    ) -> some View {
        JinSettingsSection(title) {
            JinSettingsTextFieldRow("Base URL", text: baseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: model) {
                ForEach(displayedModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .onChange(of: model.wrappedValue) { _, newModel in
                normalizeResponseFormat(
                    responseFormat,
                    provider: timestampProvider,
                    model: newModel
                )
            }
            .onAppear {
                normalizeResponseFormat(
                    responseFormat,
                    provider: timestampProvider,
                    model: model.wrappedValue
                )
            }

            if let translateToEnglish, capabilities.supportsTranslation {
                JinSettingsToggleRow("Translate to English", isOn: translateToEnglish)
            }

            switch capabilities.languageParameter {
            case .none:
                EmptyView()
            case .single:
                JinSettingsTextFieldRow(
                    "Language",
                    prompt: "auto-detect",
                    supportingText: capabilities.timestampsConflictWithLanguage
                        ? "Not compatible with timestamps — set one or the other."
                        : nil,
                    text: language,
                    usesMonospacedFont: true
                )
            case .multiple:
                JinSettingsTextFieldRow(
                    "Languages",
                    prompt: "auto-detect",
                    supportingText: "Comma-separated ISO-639-1 codes, e.g. en, fr. This model accepts several at once.",
                    text: language,
                    usesMonospacedFont: true
                )
            }

            if let keywords, capabilities.supportsKeywords {
                JinSettingsTextFieldRow(
                    "Keywords",
                    prompt: "product names, acronyms",
                    supportingText: "Comma-separated terms to bias the transcript toward.",
                    text: keywords
                )
            }

            if capabilities.supportsPrompt {
                JinSettingsTextFieldRow(
                    "Prompt",
                    text: prompt
                )
            }

            if capabilities.responseFormats.count > 1 {
                JinSettingsPickerRow("Response Format", selection: responseFormat) {
                    ForEach(capabilities.responseFormats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
            }

            if let diarize, capabilities.supportsDiarization {
                JinSettingsToggleRow("Diarize", isOn: diarize)
                    .help("Annotate which speaker is talking.")
            }

            if capabilities.supportsTemperature {
                JinSettingsSliderValueRow(
                    title: "Temperature",
                    value: temperature,
                    range: 0.0...1.0,
                    step: 0.05
                )
            }

            if !capabilities.timestampGranularities.isEmpty {
                timestampGranularityDisclosure(provider: timestampProvider)
            }
        }
    }

    /// A stored format the newly selected model rejects would otherwise sit in the picker
    /// until the next 400.
    func normalizeResponseFormat(
        _ responseFormat: Binding<String>,
        provider: SpeechToTextProvider,
        model: String
    ) {
        let supported = capabilities(for: provider, model: model).responseFormats
        guard !supported.isEmpty, !supported.contains(responseFormat.wrappedValue) else { return }
        responseFormat.wrappedValue = supported[0]
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
        case .openRouter:
            return openRouterTimestampGranularitiesJSON
        case .elevenlabs:
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
        case .openRouter:
            openRouterTimestampGranularitiesJSON = value
        case .elevenlabs:
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
