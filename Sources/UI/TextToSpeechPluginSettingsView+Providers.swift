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

            case .xiaomiMiMo:
                miMoSettingsSection

            case .elevenlabs:
                elevenLabsSettingsSection

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
                "Voice",
                fieldTitle: "Voice ID",
                supportingText: "Voices vary by model. Common OpenAI voices: alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer.",
                text: $openRouterVoice,
                usesMonospacedFont: true
            )

            JinSettingsPickerRow("Format", selection: $openRouterResponseFormat) {
                ForEach(Self.openRouterResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }

            JinSettingsSliderValueRow(
                title: "Speed",
                value: $openRouterSpeed,
                range: 0.25...4.0,
                step: 0.05,
                valueWidth: 64
            )

            JinSettingsTextFieldRow(
                "Instructions",
                supportingText: "OpenAI TTS family only — silently ignored by other providers.",
                text: $openRouterInstructions
            )
        }
    }

    var openAISettingsSection: some View {
        JinSettingsSection("OpenAI") {
            JinSettingsTextFieldRow("API Base URL", text: $openAIBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $openAIModel) {
                ForEach(displayedOpenAIModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            JinSettingsPickerRow("Voice", selection: $openAIVoice) {
                ForEach(Self.openAIVoices, id: \.self) { voice in
                    Text(voice).tag(voice)
                }
            }

            JinSettingsPickerRow("Format", selection: $openAIResponseFormat) {
                ForEach(Self.openAIResponseFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }

            JinSettingsSliderValueRow(
                title: "Speed",
                value: $openAISpeed,
                range: 0.25...4.0,
                step: 0.05,
                valueWidth: 64
            )

            JinSettingsTextFieldRow(
                "Instructions",
                text: $openAIInstructions
            )
        }
    }

    var groqSettingsSection: some View {
        JinSettingsSection("Groq") {
            JinSettingsTextFieldRow("API Base URL", text: $groqBaseURL, usesMonospacedFont: true)

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
            JinSettingsTextFieldRow("API Base URL", text: $miMoBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $miMoModel) {
                ForEach(displayedMiMoModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .onChange(of: miMoModel) { _, _ in
                normalizeMiMoVoiceIfNeeded()
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

            JinSettingsTextFieldRow(
                miMoModel == MiMoModelIDs.ttsV25VoiceDesign ? "Voice Design" : "Style",
                fieldTitle: "Describe voice or speaking style",
                supportingText: miMoModel == MiMoModelIDs.ttsV25VoiceDesign ? "Required." : "Optional.",
                text: $miMoStyleInstruction
            )
        }
    }

    var elevenLabsSettingsSection: some View {
        JinSettingsSection("ElevenLabs") {
            JinSettingsTextFieldRow("API Base URL", text: $elevenLabsBaseURL, usesMonospacedFont: true)

            JinSettingsPickerRow("Model", selection: $elevenLabsModelID) {
                ForEach(displayedElevenLabsModels) { model in
                    Text(model.name).tag(model.id)
                }
            }

            if !elevenLabsVoices.isEmpty {
                JinSettingsControlRow("Voice") {
                    HStack {
                        JinSettingsMenuPicker("Voice", selection: $elevenLabsVoiceID) {
                            ForEach(elevenLabsVoices) { voice in
                                Text(voice.name).tag(voice.voiceId)
                            }
                        }
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

            JinSettingsPickerRow("Output Format", selection: $elevenLabsOutputFormat) {
                ForEach(Self.elevenLabsOutputFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }

            Stepper("Optimize latency: \(elevenLabsOptimizeStreamingLatency)", value: $elevenLabsOptimizeStreamingLatency, in: 0...4)

            JinSettingsToggleRow("Enable logging", isOn: $elevenLabsEnableLogging)

            DisclosureGroup("Voice Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    JinSettingsSliderValueRow(
                        title: "Stability",
                        value: $elevenLabsStability,
                        range: 0.0...1.0,
                        step: 0.01,
                        labelWidth: 88
                    )
                    JinSettingsSliderValueRow(
                        title: "Similarity",
                        value: $elevenLabsSimilarityBoost,
                        range: 0.0...1.0,
                        step: 0.01,
                        labelWidth: 88
                    )
                    JinSettingsSliderValueRow(
                        title: "Style",
                        value: $elevenLabsStyle,
                        range: 0.0...1.0,
                        step: 0.01,
                        labelWidth: 88
                    )
                    Toggle("Use speaker boost", isOn: $elevenLabsUseSpeakerBoost)
                }
                .padding(.top, 6)
            }
        }
    }

    var providerErrorSection: some View {
        JinSettingsSection("Unknown Provider", style: .plain) {
            JinSettingsErrorText(text: providerErrorMessage(for: providerRaw))
        }
    }

}
