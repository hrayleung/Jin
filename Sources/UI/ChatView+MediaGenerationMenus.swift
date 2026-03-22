import SwiftUI
import SwiftData

// MARK: - Media Generation Menus

extension ChatView {

    @ViewBuilder
    var imageGenerationMenuContent: some View {
        if providerType == .xai {
            XAIImageGenerationMenuView(
                isConfigured: isImageGenerationConfigured,
                currentCount: controls.xaiImageGeneration?.count,
                selectedAspectRatio: controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio,
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
                onReset: {
                    controls.xaiImageGeneration = nil
                    persistControlsToConversation()
                }
            )
        } else if providerType == .openai || providerType == .openaiWebSocket {
            OpenAIImageGenerationMenuView(
                isConfigured: isImageGenerationConfigured,
                isGPTImageModel: lowerModelID.hasPrefix("gpt-image"),
                isDallE3: lowerModelID.hasPrefix("dall-e-3"),
                showsInputFidelity: lowerModelID == "gpt-image-1",
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

        // If background is transparent, ensure output format supports transparency
        if draft.background == .transparent {
            if let format = draft.outputFormat, format == .jpeg {
                draft.outputFormat = .png
            }
        }

        // Clear compression if format doesn't support it
        if let format = draft.outputFormat, format == .png {
            draft.outputCompression = nil
        }
        if draft.outputFormat == nil {
            draft.outputCompression = nil
        }

        controls.openaiImageGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateXAIImageGeneration(_ mutate: (inout XAIImageGenerationControls) -> Void) {
        var draft = controls.xaiImageGeneration ?? XAIImageGenerationControls()
        mutate(&draft)

        // These legacy fields are not supported by current xAI image APIs.
        draft.quality = nil
        draft.style = nil
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
                isVeo3: GoogleVideoGenerationCore.isVeo3OrLater(conversationEntity.modelID),
                isVertexProvider: providerType == .vertexai,
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
            XAIVideoGenerationMenuView(
                isConfigured: isVideoGenerationConfigured,
                currentDuration: controls.xaiVideoGeneration?.duration,
                currentAspectRatio: controls.xaiVideoGeneration?.aspectRatio,
                currentResolution: controls.xaiVideoGeneration?.resolution,
                menuItemLabel: { title, isSelected in
                    menuItemLabel(title, isSelected: isSelected)
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
        default:
            EmptyView()
        }
    }

    func updateXAIVideoGeneration(_ mutate: (inout XAIVideoGenerationControls) -> Void) {
        var draft = controls.xaiVideoGeneration ?? XAIVideoGenerationControls()
        mutate(&draft)
        controls.xaiVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    func updateGoogleVideoGeneration(_ mutate: (inout GoogleVideoGenerationControls) -> Void) {
        var draft = controls.googleVideoGeneration ?? GoogleVideoGenerationControls()
        mutate(&draft)
        controls.googleVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }
}
