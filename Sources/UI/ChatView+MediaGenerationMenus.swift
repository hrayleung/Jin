import SwiftUI
import SwiftData

// MARK: - Media Generation Menus

extension ChatView {

    @ViewBuilder
    var imageGenerationMenuContent: some View {
        if providerType == .xai {
            XAIImageGenerationMenuView(
                isConfigured: isImageGenerationConfigured,
                supportsResolution: XAIModelSupport.supportsImageResolutionControl(lowerModelID),
                supportsQuality: XAIModelSupport.supportsImageQualityControl(lowerModelID),
                currentCount: controls.xaiImageGeneration?.count,
                selectedAspectRatio: controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio,
                currentResolution: controls.xaiImageGeneration?.resolution,
                currentQuality: controls.xaiImageGeneration?.quality,
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetCount: { value in
                    updateXAIImageGeneration { $0.count = value }
                },
                onSetAspectRatio: { value in
                    if let value {
                        updateXAIImageGeneration {
                            $0.aspectRatio = value
                            $0.size = nil
                        }
                    } else {
                        updateXAIImageGeneration {
                            $0.aspectRatio = nil
                            $0.size = nil
                        }
                    }
                },
                onSetResolution: { value in
                    updateXAIImageGeneration { $0.resolution = value }
                },
                onSetQuality: { value in
                    updateXAIImageGeneration { $0.quality = value }
                },
                onReset: {
                    controls.xaiImageGeneration = nil
                    persistControlsToConversation()
                }
            )
        } else if providerType == .openai || providerType == .openaiWebSocket {
            let openAIImageProfile = OpenAIImageModelSupport.profile(for: lowerModelID)
            OpenAIImageGenerationMenuView(
                isConfigured: isImageGenerationConfigured,
                availableSizes: openAIImageProfile?.presetSizes ?? [],
                supportsCustomSizeEditor: openAIImageProfile?.supportsCustomSize == true,
                availableQualities: openAIImageProfile?.qualityOptions ?? [],
                showsStyle: openAIImageProfile?.supportsStyle == true,
                availableBackgrounds: openAIImageProfile?.backgroundOptions ?? [],
                showsOutputFormat: openAIImageProfile?.supportsOutputFormat == true,
                showsModeration: openAIImageProfile?.supportsModeration == true,
                showsInputFidelity: openAIImageProfile?.supportsInputFidelity == true,
                currentCount: controls.openaiImageGeneration?.count,
                currentSize: controls.openaiImageGeneration?.size,
                currentQuality: controls.openaiImageGeneration?.quality,
                currentStyle: controls.openaiImageGeneration?.style,
                currentBackground: controls.openaiImageGeneration?.background,
                currentOutputFormat: controls.openaiImageGeneration?.outputFormat,
                currentOutputCompression: controls.openaiImageGeneration?.outputCompression,
                currentModeration: controls.openaiImageGeneration?.moderation,
                currentInputFidelity: controls.openaiImageGeneration?.inputFidelity,
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetCount: { value in
                    updateOpenAIImageGeneration { $0.count = value }
                },
                onSetSize: { value in
                    updateOpenAIImageGeneration { $0.size = value }
                },
                onShowCustomSizeEditor: {
                    presentOpenAIImageCustomSizeSheet()
                },
                onSetQuality: { value in
                    updateOpenAIImageGeneration { $0.quality = value }
                },
                onSetStyle: { value in
                    updateOpenAIImageGeneration { $0.style = value }
                },
                onSetBackground: { value in
                    updateOpenAIImageGeneration { $0.background = value }
                },
                onSetOutputFormat: { value in
                    updateOpenAIImageGeneration { $0.outputFormat = value }
                },
                onSetOutputCompression: { value in
                    updateOpenAIImageGeneration { $0.outputCompression = value }
                },
                onSetModeration: { value in
                    updateOpenAIImageGeneration { $0.moderation = value }
                },
                onSetInputFidelity: { value in
                    updateOpenAIImageGeneration { $0.inputFidelity = value }
                },
                onReset: {
                    controls.openaiImageGeneration = nil
                    persistControlsToConversation()
                }
            )
        } else {
            Button("Edit…") {
                openImageGenerationEditor()
            }

            if isImageGenerationConfigured {
                Divider()
                Button("Reset", role: .destructive) {
                    controls.imageGeneration = nil
                    persistControlsToConversation()
                }
            }
        }
    }

    func updateOpenAIImageGeneration(_ mutate: (inout OpenAIImageGenerationControls) -> Void) {
        var draft = controls.openaiImageGeneration ?? OpenAIImageGenerationControls()
        mutate(&draft)
        normalizeOpenAIImageControls(&draft)

        controls.openaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func presentOpenAIImageCustomSizeSheet() {
        openAIImageCustomSizeTargetModelID = lowerModelID
        showingOpenAIImageCustomSizeSheet = true
    }

    func dismissOpenAIImageCustomSizeSheet() {
        showingOpenAIImageCustomSizeSheet = false
        openAIImageCustomSizeTargetModelID = ""
    }

    func handleOpenAIImageCustomSizeSave(_ size: OpenAIImageSize) {
        let targetModelID = openAIImageCustomSizeTargetModelID
        dismissOpenAIImageCustomSizeSheet()

        guard targetModelID == lowerModelID else {
            presentError("The selected OpenAI image model changed while the custom size sheet was open. Reopen the sheet and try again.")
            return
        }

        updateOpenAIImageGeneration { $0.size = size }
    }

    func updateXAIImageGeneration(_ mutate: (inout XAIImageGenerationControls) -> Void) {
        var draft = controls.xaiImageGeneration ?? XAIImageGenerationControls()
        mutate(&draft)

        draft.style = nil
        if !XAIModelSupport.supportsImageQualityControl(lowerModelID) {
            draft.quality = nil
        } else if let quality = draft.quality,
                  !XAIModelSupport.supportedImageQualities(for: lowerModelID).contains(quality) {
            draft.quality = nil
        }
        if draft.aspectRatio != nil {
            draft.size = nil
        }

        controls.xaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    @ViewBuilder
    var videoGenerationMenuContent: some View {
        switch providerType {
        case .gemini, .vertexai:
            GoogleVideoGenerationMenuView(
                productLabel: GoogleVideoGenerationCore.isOmniFlashModel(activeModelID)
                    ? "Gemini Omni Flash"
                    : "Google Veo",
                showsDuration: GoogleVideoGenerationCore.supportsDurationControl(activeModelID),
                showsPersonGeneration: GoogleVideoGenerationCore.supportsPersonGenerationControl(activeModelID),
                availableAspectRatios: GoogleVideoGenerationCore.supportedAspectRatios(for: activeModelID),
                availableResolutions: GoogleVideoGenerationCore.supportedResolutions(for: activeModelID),
                showsGenerateAudio: providerType == .vertexai
                    && GoogleVideoGenerationCore.isVeo3OrLater(activeModelID),
                isConfigured: isVideoGenerationConfigured,
                currentDurationSeconds: controls.googleVideoGeneration?.durationSeconds,
                currentAspectRatio: controls.googleVideoGeneration?.aspectRatio,
                currentResolution: controls.googleVideoGeneration?.resolution,
                currentPersonGeneration: controls.googleVideoGeneration?.personGeneration,
                generateAudioBinding: Binding(
                    get: { controls.googleVideoGeneration?.generateAudio ?? false },
                    set: { newValue in
                        updateGoogleVideoGeneration { $0.generateAudio = newValue ? true : nil }
                    }
                ),
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetDurationSeconds: { value in
                    updateGoogleVideoGeneration { $0.durationSeconds = value }
                },
                onSetAspectRatio: { value in
                    updateGoogleVideoGeneration { $0.aspectRatio = value }
                },
                onSetResolution: { value in
                    updateGoogleVideoGeneration { $0.resolution = value }
                },
                onSetPersonGeneration: { value in
                    updateGoogleVideoGeneration { $0.personGeneration = value }
                },
                onReset: {
                    controls.googleVideoGeneration = nil
                    persistControlsToConversation()
                }
            )
        case .xai:
            let mode = controls.xaiVideoGeneration?.resolvedMode ?? .auto
            let showsDuration = mode != .editVideo
            let showsAspectAndResolution = mode == .auto
                || mode == .textToVideo
                || mode == .imageToVideo
                || mode == .referenceToVideo
            XAIVideoGenerationMenuView(
                isConfigured: isVideoGenerationConfigured,
                currentMode: mode,
                currentDuration: controls.xaiVideoGeneration?.duration,
                currentAspectRatio: controls.xaiVideoGeneration?.aspectRatio,
                currentResolution: controls.xaiVideoGeneration?.resolution,
                availableModes: XAIModelSupport.availableVideoModes(for: lowerModelID),
                availableResolutions: XAIModelSupport.availableVideoResolutions(for: lowerModelID),
                showsDuration: showsDuration,
                showsAspectAndResolution: showsAspectAndResolution,
                durationOptions: XAIMediaRequestSupport.durationOptions(for: mode),
                durationHelpLabel: mode == .extendVideo
                    ? "Default (6s extension)"
                    : "Default (8s)",
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetMode: { value in
                    updateXAIVideoGeneration { draft in
                        // Always store a concrete mode (including .auto) so the checkmark
                        // and "Mode · …" title stay in sync after selection.
                        draft.mode = value
                        // Edit inherits shape from source video; clear unused fields.
                        if value == .editVideo {
                            draft.duration = nil
                            draft.aspectRatio = nil
                            draft.resolution = nil
                        } else if value == .extendVideo {
                            draft.aspectRatio = nil
                            draft.resolution = nil
                        }
                    }
                },
                onSetDuration: { value in
                    updateXAIVideoGeneration { $0.duration = value }
                },
                onSetAspectRatio: { value in
                    updateXAIVideoGeneration { $0.aspectRatio = value }
                },
                onSetResolution: { value in
                    updateXAIVideoGeneration { $0.resolution = value }
                },
                onReset: {
                    controls.xaiVideoGeneration = nil
                    persistControlsToConversation()
                }
            )
        case .openrouter:
            OpenRouterVideoGenerationMenuView(
                isConfigured: isVideoGenerationConfigured,
                supportedDurations: OpenRouterVideoModelSupport.supportedDurations(for: lowerModelID),
                supportedAspectRatios: OpenRouterVideoModelSupport.supportedAspectRatios(for: lowerModelID),
                supportedResolutions: OpenRouterVideoModelSupport.supportedResolutions(for: lowerModelID),
                currentDurationSeconds: controls.openRouterVideoGeneration?.durationSeconds,
                currentAspectRatio: controls.openRouterVideoGeneration?.aspectRatio,
                currentResolution: controls.openRouterVideoGeneration?.resolution,
                currentImageInputMode: controls.openRouterVideoGeneration?.imageInputMode,
                showsAudioToggle: OpenRouterVideoModelSupport.supportsAudio(for: lowerModelID),
                showsWatermarkToggle: OpenRouterVideoModelSupport.supportsWatermark(for: lowerModelID),
                generateAudioBinding: Binding(
                    get: { controls.openRouterVideoGeneration?.generateAudio ?? false },
                    set: { newValue in
                        updateOpenRouterVideoGeneration { $0.generateAudio = newValue ? true : nil }
                    }
                ),
                watermarkBinding: Binding(
                    get: { controls.openRouterVideoGeneration?.watermark ?? false },
                    set: { newValue in
                        updateOpenRouterVideoGeneration { $0.watermark = newValue ? true : nil }
                    }
                ),
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetDurationSeconds: { value in
                    updateOpenRouterVideoGeneration { $0.durationSeconds = value }
                },
                onSetAspectRatio: { value in
                    updateOpenRouterVideoGeneration { $0.aspectRatio = value }
                },
                onSetResolution: { value in
                    updateOpenRouterVideoGeneration { $0.resolution = value }
                },
                onSetImageInputMode: { value in
                    updateOpenRouterVideoGeneration { $0.imageInputMode = value }
                },
                onReset: {
                    controls.openRouterVideoGeneration = nil
                    persistControlsToConversation()
                }
            )
        case .together:
            TogetherVideoGenerationMenuView(
                isConfigured: isVideoGenerationConfigured,
                supportedDurations: TogetherVideoModelSupport.supportedDurations(for: lowerModelID),
                supportedAspectRatios: TogetherVideoModelSupport.supportedAspectRatios(for: lowerModelID),
                supportedResolutions: TogetherVideoModelSupport.supportedResolutions(for: lowerModelID),
                currentDurationSeconds: controls.togetherVideoGeneration?.durationSeconds,
                currentAspectRatio: controls.togetherVideoGeneration?.aspectRatio,
                currentResolution: controls.togetherVideoGeneration?.resolution,
                currentImageInputMode: controls.togetherVideoGeneration?.imageInputMode,
                showsAudioToggle: TogetherVideoModelSupport.supportsAudio(for: lowerModelID),
                generateAudioBinding: Binding(
                    get: { controls.togetherVideoGeneration?.generateAudio ?? false },
                    set: { newValue in
                        updateTogetherVideoGeneration { $0.generateAudio = newValue ? true : nil }
                    }
                ),
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
                },
                onSetDurationSeconds: { value in
                    updateTogetherVideoGeneration { $0.durationSeconds = value }
                },
                onSetAspectRatio: { value in
                    updateTogetherVideoGeneration { $0.aspectRatio = value }
                },
                onSetResolution: { value in
                    updateTogetherVideoGeneration { $0.resolution = value }
                },
                onSetImageInputMode: { value in
                    updateTogetherVideoGeneration { $0.imageInputMode = value }
                },
                onReset: {
                    controls.togetherVideoGeneration = nil
                    persistControlsToConversation()
                }
            )
        default:
            EmptyView()
        }
    }

    func updateXAIVideoGeneration(_ mutate: (inout XAIVideoGenerationControls) -> Void) {
        var draft = controls.xaiVideoGeneration ?? XAIVideoGenerationControls()
        mutate(&draft)
        // Keep mode-only configuration (e.g. mode = .referenceToVideo with default shape).
        controls.xaiVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateGoogleVideoGeneration(_ mutate: (inout GoogleVideoGenerationControls) -> Void) {
        var draft = controls.googleVideoGeneration ?? GoogleVideoGenerationControls()
        mutate(&draft)
        controls.googleVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateOpenRouterVideoGeneration(_ mutate: (inout OpenRouterVideoGenerationControls) -> Void) {
        var draft = controls.openRouterVideoGeneration ?? OpenRouterVideoGenerationControls()
        mutate(&draft)
        controls.openRouterVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateTogetherVideoGeneration(_ mutate: (inout TogetherVideoGenerationControls) -> Void) {
        var draft = controls.togetherVideoGeneration ?? TogetherVideoGenerationControls()
        mutate(&draft)
        controls.togetherVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }
}
