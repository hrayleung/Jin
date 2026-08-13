import SwiftUI

// MARK: - Provider-Specific Settings & Constants

extension TextToSpeechPluginSettingsView {

    @ViewBuilder
    var providerSpecificSettings: some View {
        if let provider {
            switch provider {
            case .openai:
                openAISettingsSection

            case .openRouter:
                openRouterSettingsSection

            case .groq:
                groqSettingsSection

            case .mistral:
                mistralSettingsSection

            case .xiaomiMiMo:
                miMoSettingsSection

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

            if openRouterVoiceChoices.isEmpty {
                JinSettingsTextFieldRow(
                    "Voice",
                    prompt: "Voice ID",
                    supportingText: "This model accepts arbitrary provider voice IDs. Tap Test Connection to load the catalogs for models that publish one.",
                    text: $openRouterVoice,
                    usesMonospacedFont: true
                )
            } else {
                JinSettingsPickerRow("Voice", selection: $openRouterVoice) {
                    ForEach(openRouterVoiceChoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .onAppear {
                    normalizeOpenRouterVoiceIfNeeded()
                }
            }

            JinSettingsPickerRow("Format", selection: $openRouterResponseFormat) {
                ForEach(Self.openRouterResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .disabled(lowLatencyStreaming && supportsStreaming)
        }
    }

    var mistralSettingsSection: some View {
        JinSettingsSection("Mistral") {
            JinSettingsTextFieldRow("Base URL", text: $mistralBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $mistralModel) {
                ForEach(displayedMistralModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            if mistralVoices.isEmpty {
                Text("Enter your API key and tap Test Connection to load voices.")
                    .jinInfoCallout()
            } else {
                JinSettingsPickerRow("Voice", selection: $mistralVoiceID) {
                    ForEach(mistralVoices) { voice in
                        Text(voice.name ?? voice.id).tag(voice.id)
                    }
                }
                .onChange(of: mistralVoiceID) { _, _ in
                    NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
                }
            }

            JinSettingsPickerRow("Format", selection: $mistralResponseFormat) {
                ForEach(Self.mistralResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
        }
    }

    var openAISettingsSection: some View {
        JinSettingsSection("OpenAI") {
            JinSettingsTextFieldRow("Base URL", text: $openAIBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $openAIModel) {
                ForEach(displayedOpenAIModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .onChange(of: openAIModel) { _, _ in
                normalizeOpenAIVoiceIfNeeded()
            }

            // tts-1 / tts-1-hd predate the expressive voices.
            JinSettingsPickerRow("Voice", selection: $openAIVoice) {
                ForEach(openAIVoiceChoices, id: \.self) { voice in
                    Text(voice).tag(voice)
                }
            }
            .onAppear {
                normalizeOpenAIVoiceIfNeeded()
            }

            JinSettingsPickerRow(
                "Format",
                supportingText: lowLatencyStreaming && supportsStreaming
                    ? "Low-latency streaming requests PCM instead."
                    : nil,
                selection: $openAIResponseFormat
            ) {
                ForEach(Self.openAIResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .disabled(lowLatencyStreaming && supportsStreaming)

            JinSettingsSliderValueRow(
                title: "Speed",
                value: $openAISpeed,
                range: 0.25...4.0,
                step: 0.05,
                valueWidth: 64
            )

            // `instructions` is rejected by the tts-1 generation.
            if currentSynthesisCapabilities?.supportsInstructions == true {
                JinSettingsTextFieldRow(
                    "Instructions",
                    text: $openAIInstructions
                )
            }
        }
    }

    var groqSettingsSection: some View {
        JinSettingsSection("Groq") {
            JinSettingsTextFieldRow("Base URL", text: $groqBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $groqModel) {
                ForEach(displayedGroqModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .onChange(of: groqModel) { _, _ in
                normalizeGroqVoiceIfNeeded()
            }

            JinSettingsPickerRow("Voice", selection: $groqVoice) {
                ForEach(groqVoiceChoices, id: \.self) { voice in
                    Text(voice).tag(voice)
                }
            }
            .onAppear {
                normalizeGroqVoiceIfNeeded()
            }

            JinSettingsPickerRow("Format", selection: $groqResponseFormat) {
                Text("wav").tag("wav")
            }
        }
    }

    var miMoSettingsSection: some View {
        JinSettingsSection("Xiaomi MiMo") {
            JinSettingsTextFieldRow("Base URL", text: $miMoBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $miMoModel) {
                ForEach(displayedMiMoModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .onChange(of: miMoModel) { _, _ in
                normalizeMiMoVoiceIfNeeded()
                normalizeMiMoResponseFormatIfNeeded()
            }

            if miMoModel != MiMoModelIDs.ttsV25VoiceDesign && miMoModel != MiMoModelIDs.ttsV25VoiceClone {
                JinSettingsPickerRow("Voice", selection: $miMoVoice) {
                    ForEach(miMoVoiceChoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
                .onAppear {
                    normalizeMiMoVoiceIfNeeded()
                }
            }

            if miMoModel == MiMoModelIDs.ttsV25VoiceClone {
                JinSettingsControlRow("Voice Sample", supportingText: "Required for VoiceClone. Use an mp3 or wav sample.") {
                    HStack {
                        JinSettingsTextField(
                            "Voice sample path",
                            text: $miMoVoiceCloneSamplePath,
                            usesMonospacedFont: true
                        )

                        Button("Choose…") {
                            chooseMiMoVoiceCloneSample()
                        }
                    }
                }
            }

            JinSettingsPickerRow("Format", selection: $miMoResponseFormat) {
                ForEach(MiMoModelIDs.textToSpeechResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .disabled(lowLatencyStreaming && supportsStreaming)
            .onAppear {
                normalizeMiMoResponseFormatIfNeeded()
            }

            JinSettingsTextFieldRow(
                miMoModel == MiMoModelIDs.ttsV25VoiceDesign ? "Voice Design" : "Style",
                prompt: "Describe voice or speaking style",
                supportingText: miMoModel == MiMoModelIDs.ttsV25VoiceDesign ? "Required." : "Optional.",
                text: $miMoStyleInstruction
            )
        }
    }

    var elevenLabsSettingsSection: some View {
        JinSettingsSection("ElevenLabs") {
            JinSettingsTextFieldRow("Base URL", text: $elevenLabsBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $elevenLabsModelID) {
                ForEach(displayedElevenLabsModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            if !elevenLabsVoices.isEmpty {
                JinSettingsControlRow("Voice") {
                    HStack(spacing: JinSpacing.small) {
                        Picker("Voice", selection: $elevenLabsVoiceID) {
                            ForEach(elevenLabsVoices) { voice in
                                Text(voice.name).tag(voice.voiceId)
                            }
                        }
                        .labelsHidden()
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
                Text("Enter your API key and tap Test Connection to load voices.")
                    .jinInfoCallout()
            }

            JinSettingsPickerRow(
                "Output Format",
                supportingText: lowLatencyStreaming && supportsStreaming
                    ? "Low-latency streaming requests pcm_24000 instead."
                    : nil,
                selection: $elevenLabsOutputFormat
            ) {
                ForEach(Self.elevenLabsOutputFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .disabled(lowLatencyStreaming && supportsStreaming)

            Stepper("Optimize latency: \(elevenLabsOptimizeStreamingLatency)", value: $elevenLabsOptimizeStreamingLatency, in: 0...4)

            JinSettingsToggleRow("Enable logging", isOn: $elevenLabsEnableLogging)

            DisclosureGroup("Voice Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    // v3 accepts only the three named stability modes.
                    if let stabilityValues = currentSynthesisCapabilities?.stabilityValues {
                        JinSettingsPickerRow(
                            "Stability",
                            supportingText: "Eleven v3 supports these three modes only.",
                            selection: $elevenLabsStability
                        ) {
                            ForEach(stabilityValues, id: \.self) { value in
                                Text(Self.elevenLabsStabilityLabel(value)).tag(value)
                            }
                        }
                    } else {
                        JinSettingsSliderValueRow(
                            title: "Stability",
                            value: $elevenLabsStability,
                            range: 0.0...1.0,
                            step: 0.01
                        )
                    }
                    JinSettingsSliderValueRow(
                        title: "Similarity",
                        value: $elevenLabsSimilarityBoost,
                        range: 0.0...1.0,
                        step: 0.01
                    )
                    JinSettingsSliderValueRow(
                        title: "Style",
                        value: $elevenLabsStyle,
                        range: 0.0...1.0,
                        step: 0.01
                    )
                    // `speed` is rejected by the v3 models.
                    if currentSynthesisCapabilities?.supportsSpeed == true {
                        JinSettingsSliderValueRow(
                            title: "Speed",
                            value: $elevenLabsSpeed,
                            range: 0.7...1.2,
                            step: 0.01
                        )
                    }
                    Toggle("Use speaker boost", isOn: $elevenLabsUseSpeakerBoost)
                }
                .padding(.top, 6)
            }
        }
    }

    static func elevenLabsStabilityLabel(_ value: Double) -> String {
        switch value {
        case 0.0: return "Creative (0.0)"
        case 1.0: return "Robust (1.0)"
        default: return "Natural (0.5)"
        }
    }

    var providerErrorSection: some View {
        JinSettingsSection("Unknown Provider") {
            JinSettingsErrorText(text: providerErrorMessage(for: providerRaw))
        }
    }

}
