import SwiftUI

// MARK: - Composer Views & Controls Row

extension ChatView {

    var composerOverlay: some View {
        CompactComposerOverlayView(
            messageText: $messageText,
            remoteVideoURLText: $remoteVideoInputURLText,
            draftAttachments: $draftAttachments,
            isComposerDropTargeted: $isComposerDropTargeted,
            isComposerFocused: $isComposerFocused,
            composerTextContentHeight: $composerTextContentHeight,
            sendWithCommandEnter: sendWithCommandEnter,
            isBusy: isBusy,
            canSendDraft: canSendDraft,
            showsRemoteVideoURLField: supportsExplicitRemoteVideoURLInput,
            isPreparingToSend: isPreparingToSend,
            prepareToSendStatus: prepareToSendStatus,
            isRecording: speechToTextManager.isRecording,
            isTranscribing: speechToTextManager.isTranscribing,
            recordingDurationText: formattedRecordingDuration,
            transcribingStatusText: speechToTextUsesAudioAttachment ? "Attaching audio\u{2026}" : "Transcribing\u{2026}",
            onDropFileURLs: handleDroppedFileURLs,
            onDropImages: handleDroppedImages,
            onSubmit: handleComposerSubmit,
            onCancel: handleComposerCancel,
            onRemoveAttachment: removeDraftAttachment,
            onExpand: { isExpandedComposerPresented = true },
            onHide: toggleComposerVisibility,
            onSend: sendMessage,
            slashCommandServers: slashCommandMCPItems,
            isSlashCommandActive: isSlashMCPPopoverVisible,
            slashCommandFilterText: slashMCPFilterText,
            slashCommandHighlightedIndex: slashMCPHighlightedIndex,
            perMessageMCPChips: perMessageMCPChips,
            onSlashCommandSelectServer: handleSlashCommandSelectServer,
            onSlashCommandDismiss: dismissSlashCommandPopover,
            onRemovePerMessageMCPServer: removePerMessageMCPServer,
            onInterceptKeyDown: isSlashMCPPopoverVisible ? handleSlashCommandKeyDown : nil
        ) {
            composerControlsRow
        }
        .onChange(of: messageText) { _, newValue in
            updateSlashCommandState(for: newValue, target: .composer)
        }
    }

    @ViewBuilder
    var composerControlsRow: some View {
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

            if supportsReasoningControl {
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

            if supportsCodexSessionControl {
                composerButtonControl(
                    systemName: "terminal",
                    isActive: codexSessionOverrideCount > 0,
                    badgeText: codexSessionBadgeText,
                    help: codexSessionHelpText,
                    action: openCodexSessionSettingsEditor
                )
            }

            if isAgentModeConfigured {
                composerButtonControl(
                    systemName: "terminal.fill",
                    isActive: isAgentModeActive,
                    badgeText: isAgentModeActive ? "On" : nil,
                    help: isAgentModeActive ? "Agent Mode: On" : "Agent Mode: Off"
                ) {
                    isAgentModePopoverPresented.toggle()
                }
                .popover(isPresented: $isAgentModePopoverPresented, arrowEdge: .bottom) {
                    AgentModePopoverView(isActive: $isAgentModeActive)
                }
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

            Spacer(minLength: 0)
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

    var floatingComposer: some View {
        VStack(spacing: JinSpacing.small) {
            if isComposerHidden {
                CollapsedComposerBar(
                    hasContent: !messageText.isEmpty || !draftAttachments.isEmpty,
                    onExpand: showComposer
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if isSlashMCPPopoverVisible, slashCommandTarget == .composer {
                    SlashCommandMCPPopover(
                        servers: slashCommandMCPItems,
                        filterText: slashMCPFilterText,
                        highlightedIndex: slashMCPHighlightedIndex,
                        onSelectServer: handleSlashCommandSelectServer,
                        onDismiss: dismissSlashCommandPopover
                    )
                    .padding(.horizontal, JinSpacing.medium)
                    .frame(maxWidth: 800)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                composerOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isComposerHidden)
        .animation(.easeOut(duration: 0.15), value: isSlashMCPPopoverVisible)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ComposerHeightPreferenceKey.self, value: geo.size.height)
            }
        }
    }

    func showComposer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isComposerHidden = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isComposerFocused = true
        }
    }

    func toggleComposerVisibility() {
        if isComposerHidden {
            showComposer()
        } else {
            isComposerFocused = false
            if isExpandedComposerPresented {
                isExpandedComposerPresented = false
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                isComposerHidden = true
            }
        }
    }

    @ViewBuilder
    var expandedComposerOverlay: some View {
        if isExpandedComposerPresented {
            let isComposerTarget = slashCommandTarget == .composer
            ExpandedComposerOverlay(
                messageText: $messageText,
                remoteVideoURLText: $remoteVideoInputURLText,
                draftAttachments: $draftAttachments,
                isPresented: $isExpandedComposerPresented,
                isComposerDropTargeted: $isComposerDropTargeted,
                isBusy: isBusy,
                canSendDraft: canSendDraft,
                showsRemoteVideoURLField: supportsExplicitRemoteVideoURLInput,
                onSend: {
                    isExpandedComposerPresented = false
                    sendMessage()
                },
                onDropFileURLs: handleDroppedFileURLs,
                onDropImages: handleDroppedImages,
                onRemoveAttachment: removeDraftAttachment,
                slashCommandServers: slashCommandMCPItems,
                isSlashCommandActive: isSlashMCPPopoverVisible && isComposerTarget,
                slashCommandFilterText: isComposerTarget ? slashMCPFilterText : "",
                slashCommandHighlightedIndex: isComposerTarget ? slashMCPHighlightedIndex : 0,
                perMessageMCPChips: perMessageMCPChips,
                onSlashCommandSelectServer: handleSlashCommandSelectServer,
                onSlashCommandDismiss: dismissSlashCommandPopover,
                onRemovePerMessageMCPServer: removePerMessageMCPServer,
                onInterceptKeyDown: (isSlashMCPPopoverVisible && isComposerTarget) ? handleSlashCommandKeyDown : nil
            )
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        }
    }

    var fullPageDropOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop to attach")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous))
        }
        .allowsHitTesting(false)
        .opacity(isFullPageDropTargeted ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isFullPageDropTargeted)
    }

    var chatFocusedActions: ChatFocusedActions {
        ChatFocusedActions(
            canAttach: !isBusy,
            canStopStreaming: isBusy,
            isComposerHidden: isComposerHidden,
            focusComposer: {
                if isComposerHidden {
                    showComposer()
                } else {
                    isComposerFocused = true
                }
            },
            openModelPicker: { isModelPickerPresented.toggle() },
            openAddModelPicker: { isAddModelPickerPresented.toggle() },
            attach: { isFileImporterPresented = true },
            stopStreaming: {
                guard isBusy else { return }
                sendMessage()
            },
            toggleExpandedComposer: {
                isExpandedComposerPresented.toggle()
            },
            toggleComposerVisibility: toggleComposerVisibility
        )
    }
}
