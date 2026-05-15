import SwiftUI

// MARK: - Composer Controls Row

extension ChatView {

    @ViewBuilder
    func composerControlsRow(showsTrailingSpacer: Bool = true) -> some View {
        let hidesManagedAgentInternalUI = ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType)

        HStack(spacing: 6) {
            if speechToTextPluginEnabled || speechToTextManagerActive {
                composerButtonControl(
                    systemName: speechToTextSystemImageName,
                    isActive: speechToTextManagerActive,
                    badgeText: speechToTextBadgeText,
                    help: speechToTextHelpText,
                    activeColor: speechToTextActiveColor,
                    disabled: isBusy || speechToTextManager.isTranscribing || (!speechToTextReadyForCurrentMode && !speechToTextManager.isRecording),
                    action: toggleSpeechToText
                )
            }

            composerButtonControl(
                systemName: "paperclip",
                isActive: !draftAttachments.isEmpty,
                badgeText: draftAttachments.isEmpty ? nil : "\(draftAttachments.count)",
                help: fileAttachmentHelpText,
                disabled: isBusy
            ) {
                isFileImporterPresented = true
            }

            composerButtonControl(
                systemName: conversationEntity.artifactsEnabled == true ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                isActive: conversationEntity.artifactsEnabled == true,
                badgeText: nil,
                help: artifactsHelpText,
                activeColor: .accentColor,
                disabled: isBusy,
                action: toggleArtifactsEnabled
            )

            if supportsPDFProcessingControl {
                composerMenuControl(
                    systemName: "doc.text.magnifyingglass",
                    isActive: resolvedPDFProcessingMode != .native,
                    badgeText: pdfProcessingBadgeText,
                    help: pdfProcessingHelpText
                ) {
                    pdfProcessingMenuContent
                }
            }

            if supportsReasoningControl && !hidesManagedAgentInternalUI {
                composerMenuControl(
                    systemName: "brain",
                    isActive: isReasoningEnabled,
                    badgeText: reasoningBadgeText,
                    help: reasoningHelpText
                ) {
                    reasoningMenuContent
                }
            }

            if supportsOpenAIServiceTierControl {
                composerMenuControl(
                    systemName: "speedometer",
                    isActive: controls.openAIServiceTier != nil,
                    badgeText: openAIServiceTierBadgeText,
                    help: openAIServiceTierHelpText
                ) {
                    openAIServiceTierMenuContent
                }
            }

            if supportsAnthropicFastModeControl {
                composerMenuControl(
                    systemName: "bolt",
                    isActive: controls.anthropicSpeed == .fast,
                    badgeText: anthropicFastModeBadgeText,
                    help: anthropicFastModeHelpText
                ) {
                    anthropicFastModeMenuContent
                }
            }

            if supportsWebSearchControl {
                composerMenuControl(
                    systemName: "globe",
                    isActive: isWebSearchEnabled,
                    badgeText: webSearchBadgeText,
                    help: webSearchHelpText
                ) {
                    webSearchMenuContent
                }
            }

            if supportsCodeExecutionControl {
                if hasCodeExecutionConfiguration {
                    composerButtonControl(
                        systemName: "chevron.left.forwardslash.chevron.right",
                        isActive: isCodeExecutionEnabled,
                        badgeText: codeExecutionBadgeText,
                        help: codeExecutionHelpText
                    ) {
                        codeExecutionEnabledBinding.wrappedValue.toggle()
                    }
                    .contextMenu {
                        Toggle("Code Execution", isOn: codeExecutionEnabledBinding)
                        Divider()
                        Button("Configure\u{2026}") {
                            openCodeExecutionSheet()
                        }
                    }
                } else {
                    composerButtonControl(
                        systemName: "chevron.left.forwardslash.chevron.right",
                        isActive: isCodeExecutionEnabled,
                        badgeText: codeExecutionBadgeText,
                        help: codeExecutionHelpText
                    ) {
                        codeExecutionEnabledBinding.wrappedValue.toggle()
                    }
                }
            }

            if supportsGoogleMapsControl {
                composerMenuControl(
                    systemName: "map",
                    isActive: isGoogleMapsEnabled,
                    badgeText: googleMapsBadgeText,
                    help: googleMapsHelpText
                ) {
                    googleMapsMenuContent
                }
            }

            if supportsContextCacheControl {
                composerMenuControl(
                    systemName: "archivebox",
                    isActive: isContextCacheEnabled,
                    badgeText: contextCacheBadgeText,
                    help: contextCacheHelpText
                ) {
                    contextCacheMenuContent
                }
            }

            if supportsMCPToolsControl {
                composerMenuControl(
                    systemName: "hammer",
                    isActive: supportsMCPToolsControl && isMCPToolsEnabled,
                    badgeText: mcpToolsBadgeText,
                    help: mcpToolsHelpText
                ) {
                    mcpToolsMenuContent
                }
            }

            if supportsClaudeManagedAgentSessionControl {
                composerButtonControl(
                    systemName: "person.crop.square",
                    isActive: claudeManagedAgentSessionOverrideCount > 0,
                    badgeText: claudeManagedAgentSessionBadgeText,
                    help: claudeManagedAgentSessionHelpText,
                    action: openClaudeManagedAgentSessionSettingsEditor
                )
            }

            if supportsImageGenerationControl {
                composerMenuControl(
                    systemName: "photo",
                    isActive: isImageGenerationConfigured,
                    badgeText: imageGenerationBadgeText,
                    help: imageGenerationHelpText
                ) {
                    imageGenerationMenuContent
                }
            }

            if supportsVideoGenerationControl {
                composerMenuControl(
                    systemName: "film",
                    isActive: isVideoGenerationConfigured,
                    badgeText: videoGenerationBadgeText,
                    help: videoGenerationHelpText
                ) {
                    videoGenerationMenuContent
                }
            }

            if showsTrailingSpacer {
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 1)
    }

    func composerButtonControl(
        systemName: String,
        isActive: Bool,
        badgeText: String?,
        help: String,
        activeColor: Color = .accentColor,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ComposerControlIconLabel(
                systemName: systemName,
                isActive: isActive,
                badgeText: badgeText,
                activeColor: activeColor
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
    }

    func composerMenuControl<MenuContent: View>(
        systemName: String,
        isActive: Bool,
        badgeText: String?,
        help: String,
        activeColor: Color = .accentColor,
        @ViewBuilder content: @escaping () -> MenuContent
    ) -> some View {
        Menu(content: content) {
            ComposerControlIconLabel(
                systemName: systemName,
                isActive: isActive,
                badgeText: badgeText,
                activeColor: activeColor
            )
        }
        .menuStyle(.borderlessButton)
        .help(help)
    }
}
