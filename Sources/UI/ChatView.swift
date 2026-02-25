import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import Combine

struct ChatView: View {
    static let initialMessageRenderLimit = 24
    static let messageRenderPageSize = 40
    static let eagerCodeHighlightTailCount = 12
    static let pinnedBottomRefreshDelays: [TimeInterval] = [0, 0.04, 0.14]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var streamingStore: ConversationStreamingStore
    @EnvironmentObject private var responseCompletionNotifier: ResponseCompletionNotifier
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    var onPersistConversationIfNeeded: () -> Void = {}
    @Query private var providers: [ProviderConfigEntity]
    @Query private var mcpServers: [MCPServerConfigEntity]

    @AppStorage(AppPreferenceKeys.sendWithCommandEnter) private var sendWithCommandEnter = false
    @AppStorage(AppPreferenceKeys.sttAddRecordingAsFile) private var sttAddRecordingAsFile = false

    @State private var controls: GenerationControls = GenerationControls()
    @State private var messageText = ""
    @State private var remoteVideoInputURLText = ""
    @State private var draftAttachments: [DraftAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var isComposerDropTargeted = false
    @State private var isFullPageDropTargeted = false
    @State private var isComposerFocused = false
    @State private var editingUserMessageID: UUID?
    @State private var editingUserMessageText = ""
    @State private var isEditingUserMessageFocused = false
    @State private var composerHeight: CGFloat = 0
    @State private var composerTextContentHeight: CGFloat = 36
    @State private var isModelPickerPresented = false
    @State private var messageRenderLimit: Int = Self.initialMessageRenderLimit
    @State private var pendingRestoreScrollMessageID: UUID?
    @State private var isPinnedToBottom = true
    @State private var isExpandedComposerPresented = false

    // Cache expensive derived data so typing/streaming doesn't repeatedly sort/decode the entire history.
    @State private var cachedVisibleMessages: [MessageRenderItem] = []
    @State private var cachedMessagesVersion: Int = 0
    @State private var cachedMessageEntitiesByID: [UUID: MessageEntity] = [:]
    @State private var cachedToolResultsByCallID: [String: ToolResult] = [:]
    @State private var lastCacheRebuildMessageCount: Int = 0
    @State private var lastCacheRebuildUpdatedAt: Date = .distantPast

    @ObservedObject private var favoriteModelsStore = FavoriteModelsStore.shared

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingThinkingBudgetSheet = false
    @State private var thinkingBudgetDraft = ""
    @State private var maxTokensDraft = ""

    @State private var showingContextCacheSheet = false
    @State private var showingAnthropicWebSearchSheet = false
    @State private var anthropicWebSearchDomainMode: AnthropicDomainFilterMode = .none
    @State private var anthropicWebSearchAllowedDomainsDraft = ""
    @State private var anthropicWebSearchBlockedDomainsDraft = ""
    @State private var anthropicWebSearchLocationDraft = WebSearchUserLocation()
    @State private var anthropicWebSearchDraftError: String?
    @State private var contextCacheDraft = ContextCacheControls(mode: .implicit)
    @State private var contextCacheTTLPreset = ContextCacheTTLPreset.providerDefault
    @State private var contextCacheCustomTTLDraft = ""
    @State private var contextCacheMinTokensDraft = ""
    @State private var contextCacheDraftError: String?
    @State private var contextCacheAdvancedExpanded = false

    @State private var showingImageGenerationSheet = false
    @State private var imageGenerationDraft = ImageGenerationControls()
    @State private var imageGenerationSeedDraft = ""
    @State private var imageGenerationCompressionQualityDraft = ""
    @State private var imageGenerationDraftError: String?
    @State private var mistralOCRConfigured = false
    @State private var deepSeekOCRConfigured = false
    @State private var textToSpeechConfigured = false
    @State private var speechToTextConfigured = false
    @State private var mistralOCRPluginEnabled = true
    @State private var deepSeekOCRPluginEnabled = true
    @State private var textToSpeechPluginEnabled = true
    @State private var speechToTextPluginEnabled = true
    @State private var webSearchPluginEnabled = true
    @State private var webSearchPluginConfigured = false
    @State private var isPreparingToSend = false
    @State private var prepareToSendStatus: String?
    @State private var prepareToSendTask: Task<Void, Never>?
    @EnvironmentObject private var ttsPlaybackManager: TextToSpeechPlaybackManager
    @StateObject private var speechToTextManager = SpeechToTextManager()

    private let conversationTitleGenerator = ConversationTitleGenerator()

    private var isStreaming: Bool {
        streamingStore.isStreaming(conversationID: conversationEntity.id)
    }

    private var isBusy: Bool {
        isStreaming || isPreparingToSend
    }

    private var streamingMessage: StreamingMessageState? {
        streamingStore.streamingState(conversationID: conversationEntity.id)
    }

    private var streamingModelLabel: String? {
        streamingStore.streamingModelLabel(conversationID: conversationEntity.id)
    }

    private var composerOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: JinRadius.large, style: .continuous)

        return HStack(alignment: .bottom, spacing: JinSpacing.medium) {
            composerLeftColumn
            composerSendButton
        }
        .padding(JinSpacing.medium)
        .frame(maxWidth: 800)
        .background {
            shape.fill(.regularMaterial)
        }
        .overlay(
            shape.stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
        )
        .overlay(
            shape.stroke(isComposerDropTargeted ? Color.accentColor : Color.clear, lineWidth: JinStrokeWidth.emphasized)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            composerExpandButton
                .padding(.top, JinSpacing.medium)
                .padding(.trailing, JinSpacing.medium)
        }
    }

    @ViewBuilder
    private var composerLeftColumn: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            composerAttachmentChipsRow
            composerRemoteVideoInputRow
            composerTextEditor
            composerControlsRow
            composerPrepareToSendRow
            composerSpeechToTextStatusRow
        }
    }

    @ViewBuilder
    private var composerAttachmentChipsRow: some View {
        if !draftAttachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: JinSpacing.small) {
                    ForEach(draftAttachments) { attachment in
                        DraftAttachmentChip(
                            attachment: attachment,
                            onRemove: { removeDraftAttachment(attachment) }
                        )
                    }
                }
                .padding(.horizontal, JinSpacing.xSmall)
            }
        }
    }

    @ViewBuilder
    private var composerRemoteVideoInputRow: some View {
        if supportsExplicitRemoteVideoURLInput {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Public video URL (optional, for video edit)", text: $remoteVideoInputURLText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .disabled(isBusy)

                if !trimmedRemoteVideoInputURLText.isEmpty {
                    Button {
                        remoteVideoInputURLText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear video URL")
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .jinSurface(.subtle, cornerRadius: JinRadius.medium)
        }
    }

    @ViewBuilder
    private var composerTextEditor: some View {
        ZStack(alignment: .topLeading) {
            if messageText.isEmpty {
                Text("Type a message...")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .padding(.leading, 6)
            }

            DroppableTextEditor(
                text: $messageText,
                isDropTargeted: $isComposerDropTargeted,
                isFocused: $isComposerFocused,
                font: NSFont.preferredFont(forTextStyle: .body),
                useCommandEnterToSubmit: sendWithCommandEnter,
                onDropFileURLs: handleDroppedFileURLs,
                onDropImages: handleDroppedImages,
                onSubmit: handleComposerSubmit,
                onCancel: handleComposerCancel,
                onContentHeightChanged: { height in
                    let clamped = max(36, min(height, 120))
                    if abs(composerTextContentHeight - clamped) > 0.5 {
                        composerTextContentHeight = clamped
                    }
                }
            )
            .frame(height: composerTextContentHeight)
        }
    }

    @ViewBuilder
    private var composerControlsRow: some View {
        HStack(spacing: 6) {
            if speechToTextPluginEnabled || speechToTextManagerActive {
                Button { toggleSpeechToText() } label: {
                    controlIconLabel(
                        systemName: speechToTextSystemImageName,
                        isActive: speechToTextManagerActive,
                        badgeText: speechToTextBadgeText,
                        activeColor: speechToTextActiveColor
                    )
                }
                .buttonStyle(.plain)
                .help(speechToTextHelpText)
                .disabled(isBusy || speechToTextManager.isTranscribing || (!speechToTextReadyForCurrentMode && !speechToTextManager.isRecording))
            }

            Button { isFileImporterPresented = true } label: {
                controlIconLabel(
                    systemName: "paperclip",
                    isActive: !draftAttachments.isEmpty,
                    badgeText: draftAttachments.isEmpty ? nil : "\(draftAttachments.count)"
                )
            }
            .buttonStyle(.plain)
            .help(fileAttachmentHelpText)
            .disabled(isBusy)

            if supportsPDFProcessingControl {
                Menu { pdfProcessingMenuContent } label: {
                    controlIconLabel(
                        systemName: "doc.text.magnifyingglass",
                        isActive: resolvedPDFProcessingMode != .native,
                        badgeText: pdfProcessingBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(pdfProcessingHelpText)
            }

            if supportsReasoningControl {
                Menu { reasoningMenuContent } label: {
                    controlIconLabel(
                        systemName: "brain",
                        isActive: isReasoningEnabled,
                        badgeText: reasoningBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(reasoningHelpText)
            }

            if supportsWebSearchControl {
                Menu { webSearchMenuContent } label: {
                    controlIconLabel(
                        systemName: "globe",
                        isActive: isWebSearchEnabled,
                        badgeText: webSearchBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(webSearchHelpText)
            }

            if supportsContextCacheControl {
                Menu { contextCacheMenuContent } label: {
                    controlIconLabel(
                        systemName: "archivebox",
                        isActive: isContextCacheEnabled,
                        badgeText: contextCacheBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(contextCacheHelpText)
            }

            if supportsMCPToolsControl {
                Menu { mcpToolsMenuContent } label: {
                    controlIconLabel(
                        systemName: "hammer",
                        isActive: supportsMCPToolsControl && isMCPToolsEnabled,
                        badgeText: mcpToolsBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(mcpToolsHelpText)
            }

            if supportsImageGenerationControl {
                Menu { imageGenerationMenuContent } label: {
                    controlIconLabel(
                        systemName: "photo",
                        isActive: isImageGenerationConfigured,
                        badgeText: imageGenerationBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(imageGenerationHelpText)
            }

            if supportsVideoGenerationControl {
                Menu { videoGenerationMenuContent } label: {
                    controlIconLabel(
                        systemName: "film",
                        isActive: isVideoGenerationConfigured,
                        badgeText: videoGenerationBadgeText
                    )
                }
                .menuStyle(.borderlessButton)
                .help(videoGenerationHelpText)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 1)
    }

    @ViewBuilder
    private var composerPrepareToSendRow: some View {
        if isPreparingToSend, let prepareToSendStatus {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(prepareToSendStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var composerSpeechToTextStatusRow: some View {
        if speechToTextManager.isRecording {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Recording… \(formattedRecordingDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        } else if speechToTextManager.isTranscribing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(speechToTextUsesAudioAttachment ? "Attaching audio…" : "Transcribing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private var composerExpandButton: some View {
        Button {
            isExpandedComposerPresented = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand composer (\u{21E7}\u{2318}E)")
        .disabled(isBusy)
    }

    private var composerSendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                .resizable()
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 22)
                .foregroundStyle(isBusy ? Color.secondary : (canSendDraft ? Color.accentColor : .gray))
        }
        .buttonStyle(.plain)
        .disabled((!canSendDraft && !isBusy) || speechToTextManager.isRecording || speechToTextManager.isTranscribing)
        .padding(.bottom, 2)
    }

    private func chatScrollView(geometry: GeometryProxy, proxy: ScrollViewProxy) -> some View {
        func refreshPinnedBottomIfNeeded() {
            guard isPinnedToBottom else { return }

            for delay in Self.pinnedBottomRefreshDelays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }

        return ScrollView {
            let bubbleMaxWidth = maxBubbleWidth(for: geometry.size.width)
            let assistantDisplayName = conversationEntity.assistant?.displayName ?? "Assistant"
            let providerIconID = currentProviderIconID
            let toolResultsByCallID = cachedToolResultsByCallID
            let messageEntitiesByID = cachedMessageEntitiesByID

            let allMessages = cachedVisibleMessages
            let visibleMessages = Array(allMessages.suffix(messageRenderLimit))
            let hiddenCount = allMessages.count - visibleMessages.count
            let eagerCodeHighlightStartIndex = max(0, visibleMessages.count - Self.eagerCodeHighlightTailCount)

            LazyVStack(alignment: .leading, spacing: 16) {
                if hiddenCount > 0 {
                    LoadEarlierMessagesRow(
                        hiddenCount: hiddenCount,
                        pageSize: Self.messageRenderPageSize,
                        onLoad: {
                            guard let firstVisible = visibleMessages.first else { return }
                            pendingRestoreScrollMessageID = firstVisible.id
                            messageRenderLimit = min(allMessages.count, messageRenderLimit + Self.messageRenderPageSize)
                        }
                    )
                    .id("loadEarlier")
                }

                ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                    MessageRow(
                        item: message,
                        maxBubbleWidth: bubbleMaxWidth,
                        assistantDisplayName: assistantDisplayName,
                        providerIconID: providerIconID,
                        deferCodeHighlightUpgrade: index < eagerCodeHighlightStartIndex,
                        toolResultsByCallID: toolResultsByCallID,
                        actionsEnabled: !isStreaming,
                        textToSpeechEnabled: textToSpeechPluginEnabled,
                        textToSpeechConfigured: textToSpeechConfigured,
                        textToSpeechIsGenerating: ttsPlaybackManager.isGenerating(messageID: message.id),
                        textToSpeechIsPlaying: ttsPlaybackManager.isPlaying(messageID: message.id),
                        textToSpeechIsPaused: ttsPlaybackManager.isPaused(messageID: message.id),
                        onToggleSpeakAssistantMessage: { messageID, text in
                            guard let entity = messageEntitiesByID[messageID] else { return }
                            toggleSpeakAssistantMessage(entity, text: text)
                        },
                        onStopSpeakAssistantMessage: { messageID in
                            guard let entity = messageEntitiesByID[messageID] else { return }
                            stopSpeakAssistantMessage(entity)
                        },
                        onRegenerate: { messageID in
                            guard let entity = messageEntitiesByID[messageID] else { return }
                            regenerateMessage(entity)
                        },
                        onEditUserMessage: { messageID in
                            guard let entity = messageEntitiesByID[messageID] else { return }
                            beginEditingUserMessage(entity)
                        },
                        editingUserMessageID: editingUserMessageID,
                        editingUserMessageText: $editingUserMessageText,
                        editingUserMessageFocused: $isEditingUserMessageFocused,
                        onSubmitUserEdit: { messageID in
                            guard let entity = messageEntitiesByID[messageID] else { return }
                            submitEditingUserMessage(entity)
                        },
                        onCancelUserEdit: {
                            cancelEditingUserMessage()
                        }
                    )
                    .id(message.id)
                }

                // Streaming message
                if let streaming = streamingMessage {
                    StreamingMessageView(
                        state: streaming,
                        maxBubbleWidth: bubbleMaxWidth,
                        assistantDisplayName: assistantDisplayName,
                        modelLabel: streamingModelLabel,
                        providerIconID: providerIconID,
                        onContentUpdate: { }
                    )
                    .id("streaming")
                }

                Color.clear
                    .frame(height: composerHeight + 24)
                    .id("bottom")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .frame(minHeight: geometry.size.height, alignment: .bottom)
        }
        .defaultScrollAnchor(.bottom)
        .overlay(alignment: .bottomTrailing) {
            Group {
                if !isPinnedToBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPinnedToBottom)
        }
        .onScrollPinChange(isPinned: $isPinnedToBottom)
        .onChange(of: messageRenderLimit) { _, _ in
            guard let restoreID = pendingRestoreScrollMessageID else { return }
            DispatchQueue.main.async {
                proxy.scrollTo(restoreID, anchor: .top)
                pendingRestoreScrollMessageID = nil
            }
        }
        .onChange(of: conversationEntity.messages.count) { _, _ in
            refreshPinnedBottomIfNeeded()
        }
        .onChange(of: isStreaming) { wasStreaming, nowStreaming in
            guard wasStreaming, !nowStreaming else { return }
            rebuildMessageCachesIfNeeded()
            refreshPinnedBottomIfNeeded()
        }
        .onChange(of: conversationEntity.id) { _, _ in
            DispatchQueue.main.async {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Message list
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    chatScrollView(geometry: geometry, proxy: proxy)
                }
            }

            // Floating Composer
            composerOverlay
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ComposerHeightPreferenceKey.self, value: geo.size.height)
                    }
                }
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { newValue in
            if abs(composerHeight - newValue) > 0.5 {
                composerHeight = newValue
            }
        }
        .background(JinSemanticColor.detailSurface)
        .onDrop(of: [.fileURL, .image, .data], isTargeted: $isFullPageDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isFullPageDropTargeted {
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
            }
        }
        .overlay {
            if isExpandedComposerPresented {
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
                    onRemoveAttachment: removeDraftAttachment
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpandedComposerPresented)
        .toolbarBackground(JinSemanticColor.detailSurface, for: .windowToolbar)
        .navigationTitle(conversationEntity.title)
        .navigationSubtitle(currentModelName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                modelPickerButton
            }
            .jinHideSharedBackgroundIfAvailable()

            ToolbarItem(placement: .primaryAction) {
                let isStarred = conversationEntity.isStarred == true
                Button {
                    conversationEntity.isStarred = !isStarred
                    try? modelContext.save()
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(isStarred ? Color.orange : Color.primary)
                        .frame(width: 28, height: 28)
                }
                .help(isStarred ? "Unstar chat" : "Star chat")
            }
            .jinHideSharedBackgroundIfAvailable()

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAssistantInspectorPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }
                .help("Assistant Settings")
            }
            .jinHideSharedBackgroundIfAvailable()

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    onRequestDeleteConversation()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                }
                .help("Delete chat")
            }
            .jinHideSharedBackgroundIfAvailable()
        }
        .onAppear {
            isComposerFocused = true
            rebuildMessageCaches()
        }
        .onChange(of: conversationEntity.id) { _, _ in
            // Switching chats: reset transient per-chat state and rebuild caches.
            cancelEditingUserMessage()
            messageRenderLimit = Self.initialMessageRenderLimit
            pendingRestoreScrollMessageID = nil
            isPinnedToBottom = true
            isExpandedComposerPresented = false
            remoteVideoInputURLText = ""
            loadControlsFromConversation()
            rebuildMessageCaches()
        }
        .onChange(of: conversationEntity.messages.count) { _, _ in
            rebuildMessageCachesIfNeeded()
        }
        .onChange(of: conversationEntity.updatedAt) { _, _ in
            rebuildMessageCachesIfNeeded()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .movie, .audio, .pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await importAttachments(from: urls) }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
        .sheet(isPresented: $showingThinkingBudgetSheet) {
            ThinkingBudgetSheetView(
                usesEffortMode: anthropicUsesEffortMode,
                summaryText: anthropicThinkingSummaryText,
                footnoteText: anthropicThinkingFootnote,
                budgetPlaceholder: anthropicBudgetPlaceholder,
                maxTokensPlaceholder: anthropicMaxTokensPlaceholder,
                modelID: conversationEntity.modelID,
                modelMaxOutputTokens: AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID),
                supportsMaxEffort: AnthropicModelLimits.supportsMaxEffort(for: conversationEntity.modelID),
                thinkingBudgetDraft: $thinkingBudgetDraft,
                maxTokensDraft: $maxTokensDraft,
                effortSelection: anthropicEffortBinding,
                isValid: isThinkingBudgetDraftValid,
                validationWarning: thinkingBudgetValidationWarning,
                onCancel: { showingThinkingBudgetSheet = false },
                onSave: {
                    applyThinkingBudgetDraft()
                    showingThinkingBudgetSheet = false
                }
            )
        }
        .sheet(isPresented: $showingContextCacheSheet) {
            ContextCacheSheetView(
                draft: $contextCacheDraft,
                ttlPreset: $contextCacheTTLPreset,
                customTTLDraft: $contextCacheCustomTTLDraft,
                minTokensDraft: $contextCacheMinTokensDraft,
                advancedExpanded: $contextCacheAdvancedExpanded,
                draftError: $contextCacheDraftError,
                providerType: providerType,
                supportsExplicitMode: supportsExplicitContextCacheMode,
                supportsStrategy: supportsContextCacheStrategy,
                supportsTTL: supportsContextCacheTTL,
                supportsAdvancedOptions: contextCacheSupportsAdvancedOptions,
                summaryText: contextCacheSummaryText,
                guidanceText: contextCacheGuidanceText,
                isValid: isContextCacheDraftValid,
                onCancel: { showingContextCacheSheet = false },
                onSave: { applyContextCacheDraft() }
            )
        }
        .sheet(isPresented: $showingAnthropicWebSearchSheet) {
            AnthropicWebSearchSheetView(
                domainMode: $anthropicWebSearchDomainMode,
                allowedDomainsDraft: $anthropicWebSearchAllowedDomainsDraft,
                blockedDomainsDraft: $anthropicWebSearchBlockedDomainsDraft,
                locationDraft: $anthropicWebSearchLocationDraft,
                draftError: $anthropicWebSearchDraftError,
                onCancel: { showingAnthropicWebSearchSheet = false },
                onApply: { applyAnthropicWebSearchDraft() }
            )
        }
        .sheet(isPresented: $showingImageGenerationSheet) {
            ImageGenerationSheetView(
                draft: $imageGenerationDraft,
                seedDraft: $imageGenerationSeedDraft,
                compressionQualityDraft: $imageGenerationCompressionQualityDraft,
                draftError: $imageGenerationDraftError,
                providerType: providerType,
                supportsImageSizeControl: supportsCurrentModelImageSizeControl,
                isValid: isImageGenerationDraftValid,
                onCancel: { showingImageGenerationSheet = false },
                onSave: { applyImageGenerationDraft() }
            )
        }
        .task {
            loadControlsFromConversation()
            await refreshExtensionCredentialsStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pluginCredentialsDidChange)) { _ in
            Task {
                await refreshExtensionCredentialsStatus()
            }
        }
        .focusedSceneValue(
            \.chatActions,
            ChatFocusedActions(
                canAttach: !isBusy,
                canStopStreaming: isBusy,
                focusComposer: { isComposerFocused = true },
                openModelPicker: { isModelPickerPresented.toggle() },
                attach: { isFileImporterPresented = true },
                stopStreaming: {
                    guard isBusy else { return }
                    sendMessage()
                },
                toggleExpandedComposer: {
                    isExpandedComposerPresented.toggle()
                }
            )
        )
    }
    
    // MARK: - Helpers & Subviews

    private var trimmedMessageText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRemoteVideoInputURLText: String {
        remoteVideoInputURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supportsExplicitRemoteVideoURLInput: Bool {
        supportsVideoGenerationControl && providerType == .xai
    }

    private var canSendDraft: Bool {
        !trimmedMessageText.isEmpty || !draftAttachments.isEmpty
    }

    private var speechToTextManagerActive: Bool {
        speechToTextManager.isRecording || speechToTextManager.isTranscribing
    }

    private var speechToTextSystemImageName: String {
        if speechToTextManager.isTranscribing { return "waveform" }
        if speechToTextManager.isRecording { return "mic.fill" }
        return "mic"
    }

    private var speechToTextActiveColor: Color {
        speechToTextManager.isRecording ? .red : .accentColor
    }

    private var speechToTextBadgeText: String? {
        speechToTextManager.isTranscribing ? "…" : nil
    }

    private var speechToTextUsesAudioAttachment: Bool {
        sttAddRecordingAsFile && supportsAudioInput
    }

    private var speechToTextReadyForCurrentMode: Bool {
        speechToTextUsesAudioAttachment || speechToTextConfigured
    }

    private var speechToTextHelpText: String {
        if speechToTextManager.isTranscribing {
            return speechToTextUsesAudioAttachment ? "Attaching audio…" : "Transcribing…"
        }
        if speechToTextManager.isRecording {
            return speechToTextUsesAudioAttachment ? "Stop recording and attach audio" : "Stop recording"
        }
        if !speechToTextPluginEnabled { return "Speech to Text is turned off in Settings → Plugins" }
        if speechToTextUsesAudioAttachment {
            return "Record audio and attach it to the draft message"
        }
        if sttAddRecordingAsFile && !supportsAudioInput {
            if speechToTextConfigured {
                return "Current model doesn't support audio input; using transcription fallback."
            }
            return "Current model doesn't support audio input. Configure Speech to Text for transcription fallback."
        }
        if !speechToTextConfigured { return "Configure Speech to Text in Settings → Plugins → Speech to Text" }
        return "Start recording"
    }

    private var fileAttachmentHelpText: String {
        let base = supportsAudioInput
            ? "Attach images / videos / audio / PDFs"
            : "Attach images / videos / PDFs"
        return supportsNativePDF ? "\(base) (Native PDF support ✓)" : base
    }

    private var formattedRecordingDuration: String {
        let total = max(0, Int(speechToTextManager.elapsedSeconds.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func toggleSpeechToText() {
        Task { @MainActor in
            do {
                if speechToTextManager.isRecording {
                    if speechToTextUsesAudioAttachment {
                        guard draftAttachments.count < AttachmentConstants.maxDraftAttachments else {
                            throw AttachmentImportError(message: "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message.")
                        }

                        let clip = try await speechToTextManager.stopAndCollectRecording()
                        let attachment = try await AttachmentImportPipeline.importRecordedAudioClip(clip)
                        draftAttachments.append(attachment)
                        isComposerFocused = true
                        return
                    }

                    let config = try await currentSpeechToTextTranscriptionConfig()
                    let text = try await speechToTextManager.stopAndTranscribe(config: config)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if messageText.isEmpty {
                            messageText = trimmed
                        } else {
                            let separator = messageText.hasSuffix("\n") ? "\n" : "\n\n"
                            messageText += separator + trimmed
                        }
                        isComposerFocused = true
                    }
                    return
                }

                guard speechToTextPluginEnabled else { return }
                if speechToTextUsesAudioAttachment {
                    guard draftAttachments.count < AttachmentConstants.maxDraftAttachments else {
                        throw AttachmentImportError(message: "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message.")
                    }
                    try await speechToTextManager.startRecording()
                    return
                }

                _ = try await currentSpeechToTextTranscriptionConfig() // Validate configured
                try await speechToTextManager.startRecording()
            } catch {
                speechToTextManager.cancelAndCleanup()
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func removeDraftAttachment(_ attachment: DraftAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        try? FileManager.default.removeItem(at: attachment.fileURL)
    }

    private func handleDroppedFileURLs(_ urls: [URL]) -> Bool {
        var seen = Set<URL>()
        let uniqueURLs = urls.filter { seen.insert($0).inserted }
        guard !uniqueURLs.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        Task { await importAttachments(from: uniqueURLs) }
        return true
    }

    private func handleDroppedImages(_ images: [NSImage]) -> Bool {
        guard !images.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        var urls: [URL] = []
        var errors: [String] = []

        for image in images {
            guard let url = AttachmentImportPipeline.writeTemporaryPNG(from: image) else {
                errors.append("Failed to read dropped image.")
                continue
            }
            urls.append(url)
        }

        if !urls.isEmpty {
            Task { await importAttachments(from: urls) }
        }

        if !errors.isEmpty {
            errorMessage = errors.joined(separator: "\n")
            showingError = true
        }

        return true
    }

    private func handleComposerSubmit() {
        guard !isBusy else { return }
        sendMessage()
    }

    private func handleComposerCancel() -> Bool {
        guard isBusy else { return false }
        sendMessage()
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        if isBusy {
            errorMessage = "Stop generating (or wait for PDF processing) to attach files."
            showingError = true
            return true
        }

        var didScheduleWork = false
        let group = DispatchGroup()
        let lock = NSLock()

        var droppedFileURLs: [URL] = []
        var droppedTextChunks: [String] = []
        var errors: [String] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                didScheduleWork = true
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    defer { group.leave() }

                    if let url = AttachmentImportPipeline.urlFromItemProviderItem(item) {
                        lock.lock()
                        if url.isFileURL {
                            droppedFileURLs.append(url)
                        } else {
                            droppedTextChunks.append(url.absoluteString)
                        }
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSImage.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: NSImage.self) { object, error in
                    defer { group.leave() }

                    guard let image = object as? NSImage else {
                        if let error {
                            lock.lock()
                            errors.append(error.localizedDescription)
                            lock.unlock()
                        }
                        return
                    }

                    guard let tempURL = AttachmentImportPipeline.writeTemporaryPNG(from: image) else {
                        lock.lock()
                        errors.append("Failed to read dropped image.")
                        lock.unlock()
                        return
                    }

                    lock.lock()
                    droppedFileURLs.append(tempURL)
                    lock.unlock()
                }
                continue
            }

            if provider.canLoadObject(ofClass: URL.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { object, error in
                    defer { group.leave() }

                    if let url = object {
                        lock.lock()
                        if url.isFileURL {
                            droppedFileURLs.append(url)
                        } else {
                            droppedTextChunks.append(url.absoluteString)
                        }
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                didScheduleWork = true
                group.enter()
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    defer { group.leave() }

                    if let text = object as? String {
                        let parsed = AttachmentImportPipeline.parseDroppedString(text)
                        lock.lock()
                        droppedFileURLs.append(contentsOf: parsed.fileURLs)
                        droppedTextChunks.append(contentsOf: parsed.textChunks)
                        lock.unlock()
                        return
                    }

                    if let error {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }

            // Fallback: handle file-promise or generic data providers (e.g. PDFs
            // dragged from a browser) that don't advertise fileURL / NSImage / NSString.
            let dataTypeID = provider.registeredTypeIdentifiers.first {
                guard let ut = UTType($0) else { return false }
                return ut.conforms(to: .data)
            }
            if let dataTypeID {
                didScheduleWork = true
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: dataTypeID) { url, error in
                    defer { group.leave() }

                    guard let url else {
                        if let error {
                            lock.lock()
                            errors.append(error.localizedDescription)
                            lock.unlock()
                        }
                        return
                    }

                    // loadFileRepresentation provides a temporary file that is
                    // deleted after this callback returns — copy it somewhere stable.
                    let dir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("JinDroppedFiles", isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

                    let stableURL = dir.appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: stableURL)

                    do {
                        try FileManager.default.copyItem(at: url, to: stableURL)
                        lock.lock()
                        droppedFileURLs.append(stableURL)
                        lock.unlock()
                    } catch {
                        lock.lock()
                        errors.append(error.localizedDescription)
                        lock.unlock()
                    }
                }
                continue
            }
        }

        guard didScheduleWork else { return false }

        group.notify(queue: .main) {
            let uniqueFileURLs = Array(Set(droppedFileURLs))

            if !uniqueFileURLs.isEmpty {
                Task { await importAttachments(from: uniqueFileURLs) }
            } else if !droppedTextChunks.isEmpty {
                let insertion = droppedTextChunks
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !insertion.isEmpty {
                    if messageText.isEmpty {
                        messageText = insertion
                    } else {
                        let separator = messageText.hasSuffix("\n") ? "" : "\n"
                        messageText += separator + insertion
                    }
                }
            }

            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
                showingError = true
            }
        }

        return true
    }

    private func importAttachments(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        guard !isStreaming else { return }

        let remainingSlots = max(0, AttachmentConstants.maxDraftAttachments - draftAttachments.count)
        guard remainingSlots > 0 else {
            await MainActor.run {
                errorMessage = "You can attach up to \(AttachmentConstants.maxDraftAttachments) files per message."
                showingError = true
            }
            return
        }

        let urlsToImport = Array(urls.prefix(remainingSlots))

        let (newAttachments, errors) = await Task.detached(priority: .userInitiated) {
            await AttachmentImportPipeline.importInBackground(from: urlsToImport)
        }.value

        await MainActor.run {
            if !newAttachments.isEmpty {
                draftAttachments.append(contentsOf: newAttachments)
            }
            if !errors.isEmpty {
                errorMessage = errors.joined(separator: "\n")
                showingError = true
            }
        }
    }

    private var selectedModelInfo: ModelInfo? {
        if let model = availableModels.first(where: { $0.id == conversationEntity.modelID }) {
            return normalizedSelectedModelInfo(model)
        }
        return nil
    }

    private var resolvedModelSettings: ResolvedModelSettings? {
        guard let model = selectedModelInfo else { return nil }
        return ModelSettingsResolver.resolve(model: model, providerType: providerType)
    }

    private var lowerModelID: String {
        conversationEntity.modelID.lowercased()
    }

    private func normalizedSelectedModelInfo(_ model: ModelInfo) -> ModelInfo {
        guard providerType == .fireworks else { return model }
        return normalizedFireworksModelInfo(model)
    }

    private func normalizedFireworksModelInfo(_ model: ModelInfo) -> ModelInfo {
        let canonicalID = fireworksCanonicalModelID(model.id)
        var caps = model.capabilities
        var contextWindow = model.contextWindow
        var reasoningConfig = model.reasoningConfig
        var name = model.name
        let defaultReasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .medium)

        switch canonicalID {
        case "kimi-k2p5":
            caps.insert(.vision)
            caps.insert(.reasoning)
            contextWindow = 262_100
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "Kimi K2.5" }
        case "qwen3-omni-30b-a3b-instruct", "qwen3-omni-30b-a3b-thinking":
            caps.insert(.vision)
            caps.insert(.audio)
        case "qwen3-asr-4b", "qwen3-asr-0.6b":
            caps.insert(.audio)
        case "glm-5":
            caps.insert(.reasoning)
            contextWindow = 202_800
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "GLM-5" }
        case "glm-4p7":
            caps.insert(.reasoning)
            contextWindow = 202_800
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "GLM-4.7" }
        case "minimax-m2p5":
            caps.insert(.reasoning)
            contextWindow = 196_600
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "MiniMax M2.5" }
        case "minimax-m2p1":
            caps.insert(.reasoning)
            contextWindow = 204_800
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "MiniMax M2.1" }
        case "minimax-m2":
            caps.insert(.reasoning)
            contextWindow = 196_600
            reasoningConfig = defaultReasoningConfig
            if name == model.id { name = "MiniMax M2" }
        default:
            break
        }

        return ModelInfo(
            id: model.id,
            name: name,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            overrides: model.overrides,
            isEnabled: model.isEnabled
        )
    }

    private var isImageGenerationModelID: Bool {
        switch providerType {
        case .xai:
            return Self.xAIImageGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return Self.geminiImageGenerationModelIDs.contains(lowerModelID)
        case .openai, .openaiWebSocket, .codexAppServer, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var isVideoGenerationModelID: Bool {
        switch providerType {
        case .xai:
            return Self.xAIVideoGenerationModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return Self.googleVideoGenerationModelIDs.contains(lowerModelID)
        default:
            return false
        }
    }

    private var supportsNativePDF: Bool {
        guard !supportsMediaGenerationControl else { return false }
        if resolvedModelSettings?.capabilities.contains(.nativePDF) == true {
            return true
        }

        switch providerType {
        case .openai:
            return JinModelSupport.supportsNativePDF(providerType: .openai, modelID: lowerModelID)
        case .openaiWebSocket:
            return JinModelSupport.supportsNativePDF(providerType: .openaiWebSocket, modelID: lowerModelID)
        case .anthropic:
            return JinModelSupport.supportsNativePDF(providerType: .anthropic, modelID: lowerModelID)
        case .perplexity:
            return JinModelSupport.supportsNativePDF(providerType: .perplexity, modelID: lowerModelID)
        case .xai:
            return JinModelSupport.supportsNativePDF(providerType: .xai, modelID: lowerModelID)
        case .gemini:
            return JinModelSupport.supportsNativePDF(providerType: .gemini, modelID: lowerModelID)
        case .vertexai:
            return JinModelSupport.supportsNativePDF(providerType: .vertexai, modelID: lowerModelID)
        case .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsVision: Bool {
        resolvedModelSettings?.capabilities.contains(.vision) == true
            || supportsImageGenerationControl
            || supportsVideoGenerationControl
    }

    private var supportsAudioInput: Bool {
        if isMistralTranscriptionOnlyModelID {
            return false
        }

        if resolvedModelSettings?.capabilities.contains(.audio) == true {
            return true
        }

        if supportsMediaGenerationControl {
            return false
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            return Self.openAIAudioInputModelIDs.contains(lowerModelID)
        case .mistral:
            return Self.mistralAudioInputModelIDs.contains(lowerModelID)
        case .gemini, .vertexai:
            return Self.geminiAudioInputModelIDs.contains(lowerModelID)
        case .openrouter, .openaiCompatible, .deepinfra:
            return Self.compatibleAudioInputModelIDs.contains(lowerModelID)
        case .fireworks:
            return Self.fireworksAudioInputModelIDs.contains(lowerModelID)
        case .anthropic, .perplexity, .groq, .cohere, .xai, .deepseek, .cerebras, .codexAppServer, .none:
            return false
        }
    }

    private var isMistralTranscriptionOnlyModelID: Bool {
        providerType == .mistral
            && Self.mistralTranscriptionOnlyModelIDs.contains(lowerModelID)
    }

    private var supportsImageGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.imageGeneration) == true || isImageGenerationModelID
    }

    private var supportsVideoGenerationControl: Bool {
        resolvedModelSettings?.capabilities.contains(.videoGeneration) == true || isVideoGenerationModelID
    }

    private var supportsMediaGenerationControl: Bool {
        supportsImageGenerationControl || supportsVideoGenerationControl
    }

    private var supportsImageGenerationWebSearch: Bool {
        guard supportsImageGenerationControl else { return false }
        switch providerType {
        case .gemini, .vertexai:
            return lowerModelID != "gemini-2.5-flash-image"
        case .perplexity:
            return false
        case .openai, .openaiWebSocket, .codexAppServer, .openaiCompatible, .openrouter, .anthropic, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsPDFProcessingControl: Bool {
        // Keep PDF preprocessing available for OCR/macOS extract even on media-generation models.
        true
    }

    private var supportsCurrentModelImageSizeControl: Bool {
        lowerModelID == "gemini-3-pro-image-preview"
    }

    private var isImageGenerationConfigured: Bool {
        if providerType == .xai {
            return !(controls.xaiImageGeneration?.isEmpty ?? true)
        }
        return !(controls.imageGeneration?.isEmpty ?? true)
    }

    private var imageGenerationBadgeText: String? {
        guard supportsImageGenerationControl else { return nil }

        if providerType == .xai {
            if let ratio = controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio {
                return ratio.displayName
            }
            if let count = controls.xaiImageGeneration?.count, count > 1 {
                return "x\(count)"
            }
            return isImageGenerationConfigured ? "On" : nil
        }

        if controls.imageGeneration?.responseMode == .imageOnly {
            return "IMG"
        }
        if let ratio = controls.imageGeneration?.aspectRatio?.rawValue {
            return ratio
        }
        if controls.imageGeneration?.seed != nil {
            return "Seed"
        }
        return isImageGenerationConfigured ? "On" : nil
    }

    private var imageGenerationHelpText: String {
        guard supportsImageGenerationControl else { return "Image Generation: Not supported" }

        if providerType == .xai {
            if let ratio = controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio {
                return "Image Generation: \(ratio.displayName)"
            }
            if let count = controls.xaiImageGeneration?.count {
                return "Image Generation: Count \(count)"
            }
            return isImageGenerationConfigured ? "Image Generation: Customized" : "Image Generation: Default"
        }

        if let ratio = controls.imageGeneration?.aspectRatio?.rawValue {
            return "Image Generation: \(ratio)"
        }
        if controls.imageGeneration?.responseMode == .imageOnly {
            return "Image Generation: Image only"
        }
        return isImageGenerationConfigured ? "Image Generation: Customized" : "Image Generation: Default"
    }

    private var isVideoGenerationConfigured: Bool {
        switch providerType {
        case .gemini, .vertexai:
            return !(controls.googleVideoGeneration?.isEmpty ?? true)
        case .xai:
            return !(controls.xaiVideoGeneration?.isEmpty ?? true)
        default:
            return false
        }
    }

    private var videoGenerationBadgeText: String? {
        guard supportsVideoGenerationControl else { return nil }

        switch providerType {
        case .gemini, .vertexai:
            let gc = controls.googleVideoGeneration
            if let duration = gc?.durationSeconds { return "\(duration)s" }
            if let ratio = gc?.aspectRatio { return ratio.displayName }
            if let resolution = gc?.resolution { return resolution.displayName }
            return isVideoGenerationConfigured ? "On" : nil
        case .xai:
            if let duration = controls.xaiVideoGeneration?.duration { return "\(duration)s" }
            if let ratio = controls.xaiVideoGeneration?.aspectRatio { return ratio.displayName }
            if let resolution = controls.xaiVideoGeneration?.resolution { return resolution.displayName }
            return isVideoGenerationConfigured ? "On" : nil
        default:
            return nil
        }
    }

    private var videoGenerationHelpText: String {
        guard supportsVideoGenerationControl else { return "Video Generation: Not supported" }

        switch providerType {
        case .gemini, .vertexai:
            let gc = controls.googleVideoGeneration
            var parts: [String] = []
            if let duration = gc?.durationSeconds { parts.append("\(duration)s") }
            if let ratio = gc?.aspectRatio { parts.append(ratio.displayName) }
            if let resolution = gc?.resolution { parts.append(resolution.displayName) }
            if let audio = gc?.generateAudio, audio { parts.append("Audio") }
            if parts.isEmpty {
                return isVideoGenerationConfigured ? "Video Generation: Customized" : "Video Generation: Default"
            }
            return "Video Generation: \(parts.joined(separator: ", "))"
        case .xai:
            var parts: [String] = []
            if let duration = controls.xaiVideoGeneration?.duration { parts.append("\(duration)s") }
            if let ratio = controls.xaiVideoGeneration?.aspectRatio { parts.append(ratio.displayName) }
            if let resolution = controls.xaiVideoGeneration?.resolution { parts.append(resolution.displayName) }
            if parts.isEmpty {
                return isVideoGenerationConfigured ? "Video Generation: Customized" : "Video Generation: Default"
            }
            return "Video Generation: \(parts.joined(separator: ", "))"
        default:
            return "Video Generation: Not supported"
        }
    }

    private var resolvedPDFProcessingMode: PDFProcessingMode {
        let requested = controls.pdfProcessingMode ?? .native
        if isPDFProcessingModeAvailable(requested) {
            return requested
        }
        if supportsNativePDF {
            return .native
        }
        return defaultPDFProcessingFallbackMode
    }

    private var defaultPDFProcessingFallbackMode: PDFProcessingMode {
        if mistralOCRPluginEnabled, mistralOCRConfigured {
            return .mistralOCR
        }
        if deepSeekOCRPluginEnabled, deepSeekOCRConfigured {
            return .deepSeekOCR
        }
        return .macOSExtract
    }

    private func isPDFProcessingModeAvailable(_ mode: PDFProcessingMode) -> Bool {
        switch mode {
        case .native:
            return supportsNativePDF
        case .macOSExtract:
            return true
        case .mistralOCR:
            return mistralOCRPluginEnabled
        case .deepSeekOCR:
            return deepSeekOCRPluginEnabled
        }
    }

    private var pdfProcessingBadgeText: String? {
        switch resolvedPDFProcessingMode {
        case .native:
            return nil
        case .mistralOCR:
            return "OCR"
        case .deepSeekOCR:
            return "DS"
        case .macOSExtract:
            return "mac"
        }
    }

    private var pdfProcessingHelpText: String {
        switch resolvedPDFProcessingMode {
        case .native:
            return "PDF: Native"
        case .mistralOCR:
            return mistralOCRConfigured ? "PDF: Mistral OCR" : "PDF: Mistral OCR (API key required)"
        case .deepSeekOCR:
            return deepSeekOCRConfigured ? "PDF: DeepSeek OCR (DeepInfra)" : "PDF: DeepSeek OCR (API key required)"
        case .macOSExtract:
            return "PDF: macOS Extract"
        }
    }

    private var selectedReasoningConfig: ModelReasoningConfig? {
        if providerType == .vertexai, lowerModelID == "gemini-3-pro-image-preview" {
            return nil
        }
        return resolvedModelSettings?.reasoningConfig
    }

    private var isReasoningEnabled: Bool {
        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return true
        }
        return controls.reasoning?.enabled == true
    }

    private var isWebSearchEnabled: Bool {
        guard supportsWebSearchControl else { return false }
        switch providerType {
        case .perplexity:
            return controls.webSearch?.enabled ?? true
        case .openai, .openaiWebSocket, .codexAppServer, .openaiCompatible, .openrouter, .anthropic, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .gemini, .vertexai, .none:
            return controls.webSearch?.enabled == true
        }
    }

    private var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled == true
    }

    private var effectiveContextCacheMode: ContextCacheMode {
        if let mode = controls.contextCache?.mode {
            return mode
        }
        if providerType == .anthropic {
            return .implicit
        }
        return .off
    }

    private var isContextCacheEnabled: Bool {
        effectiveContextCacheMode != .off
    }

    private var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    private var supportsReasoningDisableToggle: Bool {
        guard supportsReasoningControl else { return false }
        if resolvedModelSettings?.reasoningCanDisable == false {
            return false
        }
        return true
    }

    private var supportsNativeWebSearchControl: Bool {
        if supportsMediaGenerationControl {
            if supportsImageGenerationControl {
                return supportsImageGenerationWebSearch
            }
            return false
        }

        if let resolvedModelSettings {
            return resolvedModelSettings.supportsWebSearch
        }

        return ModelCapabilityRegistry.supportsWebSearch(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    private var supportsBuiltinSearchPluginControl: Bool {
        guard !supportsMediaGenerationControl else { return false }
        guard resolvedModelSettings?.capabilities.contains(.toolCalling) == true else { return false }
        guard webSearchPluginEnabled, webSearchPluginConfigured else { return false }
        return true
    }

    private var supportsSearchEngineModeSwitch: Bool {
        supportsNativeWebSearchControl && supportsBuiltinSearchPluginControl
    }

    private var prefersJinSearchEngine: Bool {
        controls.searchPlugin?.preferJinSearch == true
    }

    private var usesBuiltinSearchPlugin: Bool {
        guard supportsBuiltinSearchPluginControl else { return false }
        if supportsNativeWebSearchControl {
            return prefersJinSearchEngine
        }
        return true
    }

    private var supportsWebSearchControl: Bool {
        supportsNativeWebSearchControl || supportsBuiltinSearchPluginControl
    }

    private var supportsContextCacheControl: Bool {
        // Context cache is now fully automatic and intentionally hidden from the composer UI.
        false
    }

    private var supportsExplicitContextCacheMode: Bool {
        switch providerType {
        case .gemini, .vertexai:
            return true
        case .openai, .openaiWebSocket, .codexAppServer, .openaiCompatible, .openrouter, .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsContextCacheStrategy: Bool {
        providerType == .anthropic
    }

    private var supportsContextCacheTTL: Bool {
        switch providerType {
        case .openai, .openaiWebSocket, .anthropic, .xai:
            return true
        case .codexAppServer, .openaiCompatible, .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var contextCacheSupportsAdvancedOptions: Bool {
        supportsContextCacheTTL || providerType == .openai || providerType == .xai
    }

    private var contextCacheSummaryText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Use implicit caching for normal chats, or explicit caching with a cached content resource for long reusable context."
        case .anthropic:
            return "Anthropic caches tagged prompt blocks. Keep stable system/tool prefixes to improve cache hit rates."
        case .openai, .openaiWebSocket:
            return "OpenAI uses prompt cache hints. A stable key and retention hint can improve reuse across similar prompts."
        case .xai:
            return "xAI supports prompt cache hints and optional conversation scoping for continuity across related turns."
        case .codexAppServer, .openaiCompatible, .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
            return "Context cache controls are only available for providers with native prompt caching support."
        }
    }

    private var contextCacheGuidanceText: String {
        switch providerType {
        case .gemini, .vertexai:
            return "Explicit mode requires a valid cached content resource name. Keep it stable across requests to reuse cached tokens."
        case .openai, .openaiWebSocket, .xai:
            return "Use a stable cache key when your prompt prefix is consistent."
        case .anthropic:
            return "For best results, keep system prompts and tool descriptions stable so Anthropic can reuse cacheable blocks."
        case .codexAppServer, .openaiCompatible, .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras, .none:
            return "Use explicit mode for Gemini/Vertex cached content resources. Other providers use implicit cache hints."
        }
    }

    private func automaticContextCacheControls(
        providerType: ProviderType?,
        modelID: String,
        modelCapabilities: ModelCapability?
    ) -> ContextCacheControls? {
        guard !supportsMediaGenerationControl else { return nil }
        if let modelCapabilities, !modelCapabilities.contains(.promptCaching) {
            return nil
        }

        guard let providerType else { return nil }

        let conversationID = automaticContextCacheConversationID(modelID: modelID)

        switch providerType {
        case .openai:
            return ContextCacheControls(mode: .implicit)
        case .openaiWebSocket:
            return ContextCacheControls(mode: .implicit)
        case .xai:
            return ContextCacheControls(
                mode: .implicit,
                conversationID: conversationID
            )
        case .anthropic:
            return ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .providerDefault
            )
        case .gemini, .vertexai:
            // Explicit cachedContent resources require lifecycle management.
            // Keep implicit mode so providers can still apply native cache behavior where available.
            return ContextCacheControls(mode: .implicit)
        case .codexAppServer, .openaiCompatible, .openrouter, .perplexity, .groq, .cohere, .mistral, .deepinfra, .deepseek, .fireworks, .cerebras:
            return nil
        }
    }

    private func automaticContextCacheConversationID(modelID: String) -> String {
        let conversationPart = conversationEntity.id.uuidString.lowercased()
        let modelPart = sanitizedContextCacheIdentifier(modelID, maxLength: 32)
        return "jin-conv-\(conversationPart)-\(modelPart)"
    }

    private func sanitizedContextCacheIdentifier(_ raw: String, maxLength: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let lower = raw.lowercased()
        var output = ""
        output.reserveCapacity(min(lower.count, maxLength))

        var previousWasHyphen = false
        for scalar in lower.unicodeScalars {
            guard output.count < maxLength else { break }
            let character = Character(scalar)
            if allowed.contains(character) {
                output.append(character)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                output.append("-")
                previousWasHyphen = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "model" : trimmed
    }

    private var supportsMCPToolsControl: Bool {
        guard !supportsMediaGenerationControl else { return false }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }

    private var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .gemini, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .perplexity:
            return "Reasoning: \(reasoningLabel)"
        case .openai, .openaiWebSocket, .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .xai, .deepseek, .fireworks, .cerebras, .none:
            return "Reasoning: \(reasoningLabel)"
        }
    }

    private var webSearchHelpText: String {
        guard supportsWebSearchControl else { return "Web Search: Not supported" }
        guard isWebSearchEnabled else { return "Web Search: Off" }
        return "Web Search: \(webSearchLabel)"
    }

    private var mcpToolsHelpText: String {
        guard supportsMCPToolsControl else { return "MCP Tools: Not supported" }
        guard isMCPToolsEnabled else { return "MCP Tools: Off" }
        let count = selectedMCPServerIDs.count
        if count == 0 { return "MCP Tools: On (no servers)" }
        return "MCP Tools: On (\(count) server\(count == 1 ? "" : "s"))"
    }

    private var contextCacheHelpText: String {
        guard supportsContextCacheControl else { return "Context Cache: Not supported" }
        guard isContextCacheEnabled else { return "Context Cache: Off" }
        return "Context Cache: \(contextCacheLabel)"
    }

    private var webSearchLabel: String {
        if usesBuiltinSearchPlugin {
            let provider = effectiveSearchPluginProvider.displayName
            if let maxResults = controls.searchPlugin?.maxResults {
                return "\(provider) · \(maxResults) results"
            }
            return provider
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            return (controls.webSearch?.contextSize ?? .medium).displayName
        case .perplexity:
            return (controls.webSearch?.contextSize ?? .low).displayName
        case .xai:
            return webSearchSourcesLabel
        case .codexAppServer, .openaiCompatible, .openrouter, .anthropic, .groq, .cohere, .mistral, .deepinfra, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            return "On"
        }
    }

    private var webSearchSourcesLabel: String {
        let sources = Set(controls.webSearch?.sources ?? [])
        if sources.isEmpty { return "On" }
        if sources == [.web] { return "Web" }
        if sources == [.x] { return "X" }
        return "Web + X"
    }

    private var effectiveSearchPluginProvider: SearchPluginProvider {
        if let provider = controls.searchPlugin?.provider {
            return provider
        }
        return WebSearchPluginSettingsStore.load().defaultProvider
    }

    private var reasoningBadgeText: String? {
        guard supportsReasoningControl, isReasoningEnabled else { return nil }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return nil }

        switch reasoningType {
        case .budget:
            switch controls.reasoning?.budgetTokens {
            case 1024: return "L"
            case 2048: return "M"
            case 4096: return "H"
            case 8192: return "X"
            default: return "On"
            }
        case .effort:
            guard let effort = controls.reasoning?.effort else { return "On" }
            switch effort {
            case .none: return nil
            case .minimal: return "Min"
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            case .xhigh: return "X"
            }
        case .toggle:
            return "On"
        case .none:
            return nil
        }
    }

    private var webSearchBadgeText: String? {
        guard supportsWebSearchControl, isWebSearchEnabled else { return nil }

        if usesBuiltinSearchPlugin {
            return effectiveSearchPluginProvider.shortBadge
        }

        switch providerType {
        case .openai, .openaiWebSocket:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .perplexity:
            switch controls.webSearch?.contextSize ?? .medium {
            case .low: return "L"
            case .medium: return "M"
            case .high: return "H"
            }
        case .xai:
            let sources = Set(controls.webSearch?.sources ?? [])
            if sources == [.web] { return "W" }
            if sources == [.x] { return "X" }
            if sources.contains(.web), sources.contains(.x) { return "W+X" }
            return "On"
        case .anthropic:
            return "On"
        case .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            return "On"
        }
    }

    private var mcpToolsBadgeText: String? {
        guard supportsMCPToolsControl, isMCPToolsEnabled else { return nil }
        let count = selectedMCPServerIDs.count
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    private var contextCacheLabel: String {
        let mode = effectiveContextCacheMode
        switch mode {
        case .off:
            return "Off"
        case .implicit:
            return "Implicit"
        case .explicit:
            if let name = controls.contextCache?.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return "Explicit (\(name))"
            }
            return "Explicit"
        }
    }

    private var contextCacheBadgeText: String? {
        guard supportsContextCacheControl, isContextCacheEnabled else { return nil }
        switch effectiveContextCacheMode {
        case .off:
            return nil
        case .implicit:
            return "I"
        case .explicit:
            return "E"
        }
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedMCPServerIDs: Set<String> {
        guard controls.mcpTools?.enabled == true else { return [] }
        let eligibleIDs = Set(eligibleMCPServers.map(\.id))
        if let allowlist = controls.mcpTools?.enabledServerIDs {
            return Set(allowlist).intersection(eligibleIDs)
        }
        return eligibleIDs
    }

    private func setPDFProcessingMode(_ mode: PDFProcessingMode) {
        guard isPDFProcessingModeAvailable(mode) else { return }
        controls.pdfProcessingMode = (mode == .native) ? nil : mode
        persistControlsToConversation()
    }

    @ViewBuilder
    private var pdfProcessingMenuContent: some View {
        if supportsNativePDF {
            Button { setPDFProcessingMode(.native) } label: { menuItemLabel("Native", isSelected: resolvedPDFProcessingMode == .native) }
        }

        if mistralOCRPluginEnabled {
            Button { setPDFProcessingMode(.mistralOCR) } label: { menuItemLabel("Mistral OCR", isSelected: resolvedPDFProcessingMode == .mistralOCR) }
        }

        if deepSeekOCRPluginEnabled {
            Button { setPDFProcessingMode(.deepSeekOCR) } label: { menuItemLabel("DeepSeek OCR (DeepInfra)", isSelected: resolvedPDFProcessingMode == .deepSeekOCR) }
        }

        Button { setPDFProcessingMode(.macOSExtract) } label: { menuItemLabel("macOS Extract", isSelected: resolvedPDFProcessingMode == .macOSExtract) }

        if resolvedPDFProcessingMode == .mistralOCR, !mistralOCRConfigured {
            Divider()
            Text("Set API key in Settings → Plugins → Mistral OCR.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if resolvedPDFProcessingMode == .deepSeekOCR, !deepSeekOCRConfigured {
            Divider()
            Text("Set API key in Settings → Plugins → DeepSeek OCR (DeepInfra).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !mistralOCRPluginEnabled && !deepSeekOCRPluginEnabled {
            Divider()
            Text("OCR plugins are turned off. Enable them in Settings → Plugins to show OCR modes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func controlIconLabel(systemName: String, isActive: Bool, badgeText: String?, activeColor: Color = .accentColor) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? activeColor : Color.secondary)
                .frame(width: JinControlMetrics.iconButtonHitSize, height: JinControlMetrics.iconButtonHitSize)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? JinSemanticColor.separator.opacity(0.45) : Color.clear, lineWidth: JinStrokeWidth.hairline)
                )

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, JinSpacing.xSmall)
                    .padding(.vertical, 1)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule()
                            .fill(JinSemanticColor.surface)
                    )
                    .overlay(
                        Capsule()
                            .stroke(JinSemanticColor.separator.opacity(0.7), lineWidth: JinStrokeWidth.hairline)
                    )
                    .offset(x: JinSpacing.xSmall, y: JinSpacing.xSmall)
            }
        }
    }

    private var modelPickerButton: some View {
        Button {
            isModelPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                ProviderIconView(iconID: currentProviderIconID, size: 14)
                    .frame(width: 16, height: 16)

                Text(currentModelName)
                    .font(.callout)
                    .fontWeight(.medium)

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Select model")
        .accessibilityLabel("Select model")
        .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
            ModelPickerPopover(
                favoritesStore: favoriteModelsStore,
                providers: providers,
                selectedProviderID: conversationEntity.providerID,
                selectedModelID: conversationEntity.modelID,
                onSelect: { providerID, modelID in
                    setProviderAndModel(providerID: providerID, modelID: modelID)
                    isModelPickerPresented = false
                }
            )
        }
    }

    private var currentModelName: String {
        availableModels.first(where: { $0.id == conversationEntity.modelID })?.name ?? conversationEntity.modelID
    }

    private var currentProvider: ProviderConfigEntity? {
        providers.first(where: { $0.id == conversationEntity.providerID })
    }

    private var currentProviderIconID: String? {
        currentProvider?.resolvedProviderIconID
    }

    private var availableModels: [ModelInfo] {
        currentProvider?.enabledModels ?? []
    }

    private func isFullySupportedModel(modelID: String) -> Bool {
        guard let providerType else { return false }
        return JinModelSupport.isFullySupported(providerType: providerType, modelID: modelID)
    }

    private func setProvider(_ providerID: String) {
        guard providerID != conversationEntity.providerID else { return }

        conversationEntity.providerID = providerID

        let models = availableModels
        if let preferredModelID = preferredModelID(in: models, providerID: providerID) {
            conversationEntity.modelID = preferredModelID
            normalizeControlsForCurrentSelection()
            try? modelContext.save()
            return
        }
        conversationEntity.modelID = models.first?.id ?? conversationEntity.modelID
        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    private func setModel(_ modelID: String) {
        guard modelID != conversationEntity.modelID else { return }
        conversationEntity.modelID = modelID
        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    private func setProviderAndModel(providerID: String, modelID: String) {
        guard providerID != conversationEntity.providerID || modelID != conversationEntity.modelID else { return }

        conversationEntity.providerID = providerID
        conversationEntity.modelID = modelID
        normalizeControlsForCurrentSelection()
        try? modelContext.save()
    }

    private func preferredModelID(in models: [ModelInfo], providerID: String) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let type = ProviderType(rawValue: provider.typeRaw) else {
            return nil
        }

        switch type {
        case .openai, .openaiWebSocket:
            return models.first(where: { $0.id == "gpt-5.2" })?.id
        case .anthropic:
            return models.first(where: { $0.id == "claude-opus-4-6" })?.id
                ?? models.first(where: { $0.id == "claude-sonnet-4-6" })?.id
                ?? models.first(where: { $0.id == "claude-sonnet-4-5-20250929" })?.id
        case .perplexity:
            return models.first(where: { $0.id == "sonar-pro" })?.id
                ?? models.first(where: { $0.id == "sonar" })?.id
        case .deepseek:
            return models.first(where: { $0.id == "deepseek-chat" })?.id
                ?? models.first(where: { $0.id == "deepseek-reasoner" })?.id
        case .fireworks:
            return models.first(where: { isFireworksModelID($0.id, canonicalID: "glm-5") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, canonicalID: "minimax-m2p5") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, canonicalID: "kimi-k2p5") })?.id
                ?? models.first(where: { isFireworksModelID($0.id, canonicalID: "glm-4p7") })?.id
        case .cerebras:
            return models.first(where: { $0.id == "zai-glm-4.7" })?.id
        case .gemini:
            for preferredID in Self.geminiPreferredModelOrder {
                if let exact = models.first(where: { $0.id.lowercased() == preferredID }) {
                    return exact.id
                }
            }
            return nil
        case .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .xai, .vertexai:
            return nil
        }
    }


    private func orderedConversationMessages() -> [MessageEntity] {
        conversationEntity.messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func rebuildMessageCachesIfNeeded() {
        guard conversationEntity.messages.count != lastCacheRebuildMessageCount
            || conversationEntity.updatedAt != lastCacheRebuildUpdatedAt else {
            return
        }

        rebuildMessageCaches()
    }

    private func rebuildMessageCaches() {
        let ordered = orderedConversationMessages()

        var messageEntitiesByID: [UUID: MessageEntity] = [:]
        messageEntitiesByID.reserveCapacity(ordered.count)

        var renderedItems: [MessageRenderItem] = []
        renderedItems.reserveCapacity(ordered.count)

        for entity in ordered {
            messageEntitiesByID[entity.id] = entity
            guard entity.role != "tool" else { continue }

            guard let message = try? entity.toDomain() else { continue }
            let renderedParts = renderedContentParts(content: message.content)

            renderedItems.append(
                MessageRenderItem(
                    id: entity.id,
                    role: entity.role,
                    timestamp: entity.timestamp,
                    renderedContentParts: renderedParts,
                    toolCalls: message.toolCalls ?? [],
                    searchActivities: message.searchActivities ?? [],
                    assistantModelLabel: entity.role == "assistant"
                        ? (entity.generatedModelName ?? entity.generatedModelID ?? currentModelName)
                        : nil,
                    copyText: copyableText(from: message),
                    canEditUserMessage: entity.role == "user"
                        && message.content.contains(where: { part in
                            if case .text = part { return true }
                            return false
                        })
                )
            )
        }

        cachedVisibleMessages = renderedItems
        cachedMessageEntitiesByID = messageEntitiesByID
        cachedToolResultsByCallID = toolResultsByToolCallID(in: ordered)
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = ordered.count
        lastCacheRebuildUpdatedAt = conversationEntity.updatedAt
    }

    private func renderedContentParts(content: [ContentPart]) -> [RenderedMessageContentPart] {
        content.compactMap { part in
            if case .redactedThinking = part {
                return nil
            }
            return RenderedMessageContentPart(part: part)
        }
    }

    private func regenerateMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }

        cancelEditingUserMessage()

        switch messageEntity.role {
        case "user":
            regenerateFromUserMessage(messageEntity)
        case "assistant":
            regenerateFromAssistantMessage(messageEntity)
        default:
            break
        }
    }

    private func beginEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }

        if editingUserMessageID != messageEntity.id {
            cancelEditingUserMessage()
        }

        guard let message = try? messageEntity.toDomain() else { return }
        guard let editableText = editableUserText(from: message), !editableText.isEmpty else { return }

        editingUserMessageID = messageEntity.id
        editingUserMessageText = editableText

        DispatchQueue.main.async {
            isEditingUserMessageFocused = true
        }
    }

    private func submitEditingUserMessage(_ messageEntity: MessageEntity) {
        guard !isStreaming else { return }
        guard messageEntity.role == "user" else { return }
        guard editingUserMessageID == messageEntity.id else { return }

        let trimmed = editingUserMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else {
            cancelEditingUserMessage()
            return
        }

        do {
            try updateUserMessageContent(messageEntity, newText: trimmed)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        cancelEditingUserMessage()
        regenerateFromUserMessage(messageEntity)
    }

    private func cancelEditingUserMessage() {
        editingUserMessageID = nil
        editingUserMessageText = ""
        isEditingUserMessageFocused = false
    }

    private func regenerateFromUserMessage(_ messageEntity: MessageEntity) {
        guard let keepCount = keepCountForRegeneratingUserMessage(messageEntity) else { return }
        let askedAt = Date()
        truncateConversation(keepingMessages: keepCount)
        messageEntity.timestamp = askedAt
        conversationEntity.updatedAt = askedAt
        startStreamingResponse(triggeredByUserSend: false)
    }

    private func regenerateFromAssistantMessage(_ messageEntity: MessageEntity) {
        guard let keepCount = keepCountForRegeneratingAssistantMessage(messageEntity) else { return }
        truncateConversation(keepingMessages: keepCount)
        startStreamingResponse(triggeredByUserSend: false)
    }

    private func keepCountForRegeneratingUserMessage(_ messageEntity: MessageEntity) -> Int? {
        let ordered = orderedConversationMessages()
        guard let index = ordered.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index + 1
        guard keepCount > 0 else { return nil }
        return keepCount
    }

    private func keepCountForRegeneratingAssistantMessage(_ messageEntity: MessageEntity) -> Int? {
        let ordered = orderedConversationMessages()
        guard let index = ordered.firstIndex(where: { $0.id == messageEntity.id }) else { return nil }
        let keepCount = index
        guard keepCount > 0 else { return nil }
        return keepCount
    }

    private func truncateConversation(keepingMessages keepCount: Int) {
        let ordered = orderedConversationMessages()
        let normalizedKeepCount = max(0, min(keepCount, ordered.count))
        let keepIDs = Set(ordered.prefix(normalizedKeepCount).map(\.id))
        let messagesToDelete = ordered.suffix(from: normalizedKeepCount)

        for message in messagesToDelete {
            modelContext.delete(message)
        }

        conversationEntity.messages.removeAll { !keepIDs.contains($0.id) }
        refreshConversationActivityTimestampFromLatestUserMessage()
        pendingRestoreScrollMessageID = nil
        isPinnedToBottom = true
        rebuildMessageCaches()
    }

    private func refreshConversationActivityTimestampFromLatestUserMessage() {
        let latestUserTimestamp = conversationEntity.messages
            .filter { $0.role == MessageRole.user.rawValue }
            .map(\.timestamp)
            .max()

        conversationEntity.updatedAt = latestUserTimestamp ?? conversationEntity.createdAt
    }

    private func editableUserText(from message: Message) -> String? {
        let parts = message.content.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    private func copyableText(from message: Message) -> String {
        let textParts = message.content.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if !textParts.isEmpty {
            return textParts.joined(separator: "\n\n")
        }

        let fileParts = message.content.compactMap { part -> String? in
            guard case .file(let file) = part else { return nil }
            let trimmed = file.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return fileParts.joined(separator: "\n")
    }

    private func updateUserMessageContent(_ entity: MessageEntity, newText: String) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let originalContent: [ContentPart] = (try? decoder.decode([ContentPart].self, from: entity.contentData)) ?? []
        var newContent: [ContentPart] = []
        newContent.reserveCapacity(max(1, originalContent.count))

        var didInsertText = false
        for part in originalContent {
            switch part {
            case .text:
                if !didInsertText {
                    newContent.append(.text(newText))
                    didInsertText = true
                }
            default:
                newContent.append(part)
            }
        }

        if !didInsertText {
            newContent.append(.text(newText))
        }

        entity.contentData = try encoder.encode(newContent)
    }

    private func toolResultsByToolCallID(in messageEntities: [MessageEntity]) -> [String: ToolResult] {
        var results: [String: ToolResult] = [:]
        results.reserveCapacity(8)

        let decoder = JSONDecoder()
        for entity in messageEntities where entity.role == "tool" {
            guard let data = entity.toolResultsData,
                  let toolResults = try? decoder.decode([ToolResult].self, from: data) else {
                continue
            }

            for result in toolResults {
                results[result.toolCallID] = result
            }
        }

        return results
    }

    private func maxBubbleWidth(for containerWidth: CGFloat) -> CGFloat {
        let usable = max(0, containerWidth - 32) // Message rows add horizontal padding
        return max(260, usable * 0.78)
    }

    private func resolvedSystemPrompt(conversationSystemPrompt: String?, assistant: AssistantEntity?) -> String? {
        let conversationPrompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantPrompt = assistant?.systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyLanguage = assistant?.replyLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)

        var prompt = conversationPrompt
        if prompt?.isEmpty != false {
            prompt = assistantPrompt
        }

        if let replyLanguage, !replyLanguage.isEmpty {
            if prompt?.isEmpty != false {
                prompt = "Always reply in \(replyLanguage)."
            } else {
                prompt = "\(prompt!)\n\nAlways reply in \(replyLanguage)."
            }
        }

        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func sendMessage() {
        if isStreaming {
            streamingStore.cancel(conversationID: conversationEntity.id)
            return
        }

        if isPreparingToSend {
            prepareToSendTask?.cancel()
            return
        }

        guard canSendDraft else { return }
        cancelEditingUserMessage()

        let messageTextSnapshot = trimmedMessageText
        let remoteVideoURLTextSnapshot = trimmedRemoteVideoInputURLText
        let attachmentsSnapshot = draftAttachments
        let askedAt = Date()

        let remoteVideoURLSnapshot: URL?
        do {
            remoteVideoURLSnapshot = try resolvedRemoteVideoInputURL(from: remoteVideoURLTextSnapshot)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            return
        }

        if supportsMediaGenerationControl && messageTextSnapshot.isEmpty {
            let mediaType = supportsVideoGenerationControl ? "Video" : "Image"
            errorMessage = "\(mediaType) generation models require a text prompt."
            showingError = true
            return
        }

        messageText = ""
        remoteVideoInputURLText = ""
        composerTextContentHeight = 36
        draftAttachments = []

        isPreparingToSend = true
        prepareToSendStatus = nil

        let task = Task {
            do {
                let parts = try await buildUserMessageParts(
                    messageText: messageTextSnapshot,
                    attachments: attachmentsSnapshot,
                    remoteVideoURL: remoteVideoURLSnapshot
                )

                let message = Message(role: .user, content: parts, timestamp: askedAt)
                let messageEntity = try MessageEntity.fromDomain(message)

                await MainActor.run {
                    if conversationEntity.messages.isEmpty {
                        onPersistConversationIfNeeded()
                    }

                    messageEntity.conversation = conversationEntity
                    conversationEntity.messages.append(messageEntity)
                    if conversationEntity.title == "New Chat", !isChatNamingPluginEnabled {
                        if !messageTextSnapshot.isEmpty {
                            conversationEntity.title = makeConversationTitle(from: messageTextSnapshot)
                        } else if let firstAttachment = attachmentsSnapshot.first {
                            conversationEntity.title = makeConversationTitle(from: (firstAttachment.filename as NSString).deletingPathExtension)
                        }
                    }
                    conversationEntity.updatedAt = askedAt
                    rebuildMessageCaches()
                    try? modelContext.save()
                }

                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    startStreamingResponse(triggeredByUserSend: true)
                }
            } catch is CancellationError {
                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    messageText = messageTextSnapshot
                    remoteVideoInputURLText = remoteVideoURLTextSnapshot
                    draftAttachments = attachmentsSnapshot
                }
            } catch {
                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    messageText = messageTextSnapshot
                    remoteVideoInputURLText = remoteVideoURLTextSnapshot
                    draftAttachments = attachmentsSnapshot
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }

        prepareToSendTask = task
    }

    private func buildUserMessageParts(
        messageText: String,
        attachments: [DraftAttachment],
        remoteVideoURL: URL?
    ) async throws -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(attachments.count + (messageText.isEmpty ? 0 : 1) + (remoteVideoURL == nil ? 0 : 1))

        if let remoteVideoURL {
            parts.append(.video(VideoContent(mimeType: inferredVideoMIMEType(from: remoteVideoURL), data: nil, url: remoteVideoURL)))
        }

        let pdfCount = attachments.filter(\.isPDF).count

        let requestedMode = resolvedPDFProcessingMode
        if pdfCount > 0, requestedMode == .native, !supportsNativePDF {
            throw PDFProcessingError.nativePDFNotSupported(modelName: currentModelName)
        }

        let mistralClient: MistralOCRClient?
        if pdfCount > 0, requestedMode == .mistralOCR {
            let key = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginMistralOCRAPIKey)
            let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw PDFProcessingError.mistralAPIKeyMissing
            }

            mistralClient = MistralOCRClient(apiKey: trimmed)
        } else {
            mistralClient = nil
        }

        let deepSeekClient: DeepInfraDeepSeekOCRClient?
        if pdfCount > 0, requestedMode == .deepSeekOCR {
            let key = UserDefaults.standard.string(forKey: AppPreferenceKeys.pluginDeepSeekOCRAPIKey)
            let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                throw PDFProcessingError.deepInfraAPIKeyMissing
            }

            deepSeekClient = DeepInfraDeepSeekOCRClient(apiKey: trimmed)
        } else {
            deepSeekClient = nil
        }

        var pdfOrdinal = 0
        for attachment in attachments {
            try Task.checkCancellation()

            if attachment.isImage {
                parts.append(.image(ImageContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isVideo {
                parts.append(.video(VideoContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isAudio {
                parts.append(.audio(AudioContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
                continue
            }

            if attachment.isPDF {
                pdfOrdinal += 1
                let prepared = try await preparedContentForPDF(
                    attachment,
                    requestedMode: requestedMode,
                    totalPDFCount: pdfCount,
                    pdfOrdinal: pdfOrdinal,
                    mistralClient: mistralClient,
                    deepSeekClient: deepSeekClient
                )

                parts.append(
                    .file(
                        FileContent(
                            mimeType: attachment.mimeType,
                            filename: attachment.filename,
                            data: nil,
                            url: attachment.fileURL,
                            extractedText: prepared.extractedText
                        )
                    )
                )
                parts.append(contentsOf: prepared.additionalParts)
                continue
            }

            parts.append(
                .file(
                    FileContent(
                        mimeType: attachment.mimeType,
                        filename: attachment.filename,
                        data: nil,
                        url: attachment.fileURL,
                        extractedText: attachment.extractedText
                    )
                )
            )
        }

        if !messageText.isEmpty {
            parts.append(.text(messageText))
        }

        return parts
    }

    private func resolvedRemoteVideoInputURL(from raw: String) throws -> URL? {
        guard supportsExplicitRemoteVideoURLInput else { return nil }
        guard !raw.isEmpty else { return nil }

        guard let url = URL(string: raw),
              !url.isFileURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LLMError.invalidRequest(message: "Video URL must be a valid http(s) link.")
        }

        return url
    }

    private func inferredVideoMIMEType(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        case "mpeg", "mpg": return "video/mpeg"
        case "wmv": return "video/x-ms-wmv"
        case "flv": return "video/x-flv"
        case "3gp", "3gpp": return "video/3gpp"
        default: return "video/mp4"
        }
    }

    private struct PreparedPDFContent {
        let extractedText: String?
        let additionalParts: [ContentPart]
    }

    private func preparedContentForPDF(
        _ attachment: DraftAttachment,
        requestedMode: PDFProcessingMode,
        totalPDFCount: Int,
        pdfOrdinal: Int,
        mistralClient: MistralOCRClient?,
        deepSeekClient: DeepInfraDeepSeekOCRClient?
    ) async throws -> PreparedPDFContent {
        let shouldSendNativePDF = supportsNativePDF && requestedMode == .native
        guard !shouldSendNativePDF else {
            return PreparedPDFContent(extractedText: nil, additionalParts: [])
        }

        switch requestedMode {
        case .macOSExtract:
            await MainActor.run {
                prepareToSendStatus = "Extracting PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (macOS): \(attachment.filename)"
            }

            guard let extracted = PDFKitTextExtractor.extractText(
                from: attachment.fileURL,
                maxCharacters: AttachmentConstants.maxPDFExtractedCharacters
            ) else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "macOS Extract")
            }

            var output = "macOS Extract (PDF): \(attachment.filename)\n\n\(extracted)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }

            return PreparedPDFContent(extractedText: output, additionalParts: [])

        case .mistralOCR:
            guard let mistralClient else { throw PDFProcessingError.mistralAPIKeyMissing }

            await MainActor.run {
                prepareToSendStatus = "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (Mistral): \(attachment.filename)"
            }

            guard let data = try? Data(contentsOf: attachment.fileURL) else {
                throw PDFProcessingError.fileReadFailed(filename: attachment.filename)
            }

            let includeImageBase64 = supportsVision
            let response = try await mistralClient.ocrPDF(data, includeImageBase64: includeImageBase64)
            let pages = response.pages
                .sorted { $0.index < $1.index }
            var combinedMarkdown = pages
                .map(\.markdown)
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // If Mistral returns extracted tables separately (via `table_format`), inline them so the model
            // doesn't see placeholder links like `[tbl-3.html](tbl-3.html)`.
            var tablesByID: [String: String] = [:]
            for page in pages {
                for table in page.tables ?? [] {
                    let id = table.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = table.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !id.isEmpty, !content.isEmpty else { continue }
                    tablesByID[id] = content
                    tablesByID[(id as NSString).lastPathComponent] = content
                }
            }

            if !tablesByID.isEmpty {
                combinedMarkdown = MistralOCRMarkdown.replacingTableLinks(from: combinedMarkdown) { id in
                    guard !id.isEmpty else { return "" }
                    if let content = tablesByID[id] { return content }
                    return "[\(id)](\(id))"
                }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard !combinedMarkdown.isEmpty else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR")
            }

            let textOnlyMarkdown = MistralOCRMarkdown.removingImageMarkdown(from: combinedMarkdown)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasText = !textOnlyMarkdown.isEmpty

            var imageParts: [ContentPart] = []
            var attachedImageIDs = Set<String>()
            var totalAttachedImageBytes = 0

            if includeImageBase64 {
                // Decode a limited number of extracted images and attach them for vision-capable models.
                var base64ByID: [String: String] = [:]
                var idsInPageOrder: [String] = []
                var seenIDs = Set<String>()

                for page in pages {
                    for image in page.images ?? [] {
                        let id = image.id
                        if seenIDs.insert(id).inserted {
                            idsInPageOrder.append(id)
                        }
                        if let base64 = image.imageBase64, !base64.isEmpty {
                            base64ByID[id] = base64
                        }
                    }
                }

                let referencedIDs = MistralOCRMarkdown.referencedImageIDs(in: combinedMarkdown)
                var orderedIDs: [String] = []
                orderedIDs.reserveCapacity(max(referencedIDs.count, idsInPageOrder.count))

                var used = Set<String>()
                for id in referencedIDs {
                    if used.insert(id).inserted { orderedIDs.append(id) }
                }
                for id in idsInPageOrder {
                    if used.insert(id).inserted { orderedIDs.append(id) }
                }

                for id in orderedIDs {
                    guard imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach else { break }
                    guard let base64 = base64ByID[id] else { continue }
                    guard let decoded = PDFProcessingUtilities.decodeMistralOCRImageBase64(base64, imageID: id) else { continue }
                    guard let decodedData = decoded.data else { continue }

                    let nextTotal = totalAttachedImageBytes + decodedData.count
                    guard nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes else { break }
                    totalAttachedImageBytes = nextTotal

                    attachedImageIDs.insert(id)
                    imageParts.append(.image(decoded))
                }
            }

            let extractedText: String
            if includeImageBase64 {
                let replaced = MistralOCRMarkdown.replacingImageMarkdown(from: combinedMarkdown) { id in
                    let label = attachedImageIDs.contains(id) ? "Image attached" : "Image omitted"
                    if id.isEmpty { return "[\(label)]" }
                    return "[\(label): \(id)]"
                }
                extractedText = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                extractedText = textOnlyMarkdown
            }

            if !hasText, imageParts.isEmpty {
                // Mistral may return image-only markdown placeholders for scanned PDFs. In that case,
                // text-only models should error, and vision models need extracted images attached.
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "Mistral OCR (image-only — requires vision)")
            }

            var output = extractedText
            if !hasText, !imageParts.isEmpty {
                output = "Mistral OCR extracted images (no text) from this PDF. See attached images."
            }

            let extractedImageCount = pages.reduce(0) { $0 + (($1.images ?? []).count) }
            let omittedCount = max(0, extractedImageCount - attachedImageIDs.count)
            if includeImageBase64, omittedCount > 0 {
                output += "\n\n[Note: \(omittedCount) extracted image(s) omitted due to size limits.]"
            }

            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            output = "Mistral OCR (Markdown): \(attachment.filename)\n\n\(output)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }
            return PreparedPDFContent(extractedText: output, additionalParts: imageParts)

        case .deepSeekOCR:
            guard let deepSeekClient else { throw PDFProcessingError.deepInfraAPIKeyMissing }

            let includePageImages = supportsVision
            let renderedPages = try PDFKitImageRenderer.renderAllPagesAsJPEG(from: attachment.fileURL)
            let totalPages = max(1, renderedPages.count)

            var pageMarkdown: [String] = []
            pageMarkdown.reserveCapacity(renderedPages.count)

            var imageParts: [ContentPart] = []
            var totalAttachedBytes = 0

            for rendered in renderedPages {
                try Task.checkCancellation()

                await MainActor.run {
                    prepareToSendStatus = "OCR PDF \(pdfOrdinal)/\(max(1, totalPDFCount)) (DeepSeek): \(attachment.filename) — page \(rendered.pageIndex + 1)/\(totalPages)"
                }

                let prompt = "Convert this page to Markdown. Preserve layout and tables. Return only the Markdown."
                let raw = try await deepSeekClient.ocrImage(
                    rendered.data,
                    mimeType: rendered.mimeType,
                    prompt: prompt,
                    timeoutSeconds: 120
                )

                let normalized = PDFProcessingUtilities.normalizedDeepSeekOCRMarkdown(raw)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    pageMarkdown.append(normalized)
                }

                if includePageImages,
                   imageParts.count < AttachmentConstants.maxMistralOCRImagesToAttach {
                    let nextTotal = totalAttachedBytes + rendered.data.count
                    if nextTotal <= AttachmentConstants.maxMistralOCRTotalImageBytes {
                        totalAttachedBytes = nextTotal
                        imageParts.append(.image(ImageContent(mimeType: rendered.mimeType, data: rendered.data, url: nil)))
                    }
                }
            }

            let combined = pageMarkdown
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !combined.isEmpty else {
                throw PDFProcessingError.noTextExtracted(filename: attachment.filename, method: "DeepSeek OCR (DeepInfra)")
            }

            var output = combined
            if includePageImages, !imageParts.isEmpty {
                let omitted = max(0, renderedPages.count - imageParts.count)
                output += "\n\n[Note: Attached \(imageParts.count) page image(s) for vision context.]"
                if omitted > 0 {
                    output += "\n[Note: \(omitted) page image(s) omitted due to size limits.]"
                }
            }

            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            output = "DeepSeek OCR (Markdown): \(attachment.filename)\n\n\(output)"
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.count > AttachmentConstants.maxPDFExtractedCharacters {
                let prefix = output.prefix(AttachmentConstants.maxPDFExtractedCharacters)
                output = "\(prefix)\n\n[Truncated]"
            }
            return PreparedPDFContent(extractedText: output, additionalParts: imageParts)

        case .native:
            throw PDFProcessingError.nativePDFNotSupported(modelName: currentModelName)
        }
    }

    private func makeConversationTitle(from userText: String) -> String {
        let firstLine = userText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        return String(trimmed.prefix(48))
    }

    @MainActor
    private func startStreamingResponse(triggeredByUserSend: Bool = false) {
        let conversationID = conversationEntity.id
        guard !streamingStore.isStreaming(conversationID: conversationID) else { return }

        // Re-apply model-aware normalization on every send so newly edited model
        // settings (capabilities/web search/reasoning limits) are reflected in
        // the outgoing request controls.
        normalizeControlsForCurrentSelection()

        let providerID = conversationEntity.providerID
        let modelID = conversationEntity.modelID
        let modelInfoSnapshot = selectedModelInfo
        let resolvedModelSettingsSnapshot = resolvedModelSettings
        let modelNameSnapshot = modelInfoSnapshot?.name ?? modelID
        let streamingState = streamingStore.beginSession(conversationID: conversationID, modelLabel: modelNameSnapshot)
        streamingState.reset()

        let providerConfig = providers.first(where: { $0.id == providerID }).flatMap { try? $0.toDomain() }
        let baseHistory = conversationEntity.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .compactMap { try? $0.toDomain() }
        let assistant = conversationEntity.assistant
        let systemPrompt = resolvedSystemPrompt(
            conversationSystemPrompt: conversationEntity.systemPrompt,
            assistant: assistant
        )
        var controlsToUse: GenerationControls = (try? JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData))
            ?? controls
        controlsToUse = GenerationControlsResolver.resolvedForRequest(
            base: controlsToUse,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens
        )
        controlsToUse.contextCache = automaticContextCacheControls(
            providerType: providerType,
            modelID: modelID,
            modelCapabilities: resolvedModelSettingsSnapshot?.capabilities
        )

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let maxHistoryMessages = assistant?.maxHistoryMessages
        let modelContextWindow = resolvedModelSettingsSnapshot?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let mcpServerConfigs = resolvedMCPServerConfigs(for: controlsToUse)
        let chatNamingTarget = resolvedChatNamingTarget()
        let shouldOfferBuiltinSearch = usesBuiltinSearchPlugin

        responseCompletionNotifier.prepareAuthorizationIfNeededWhileActive()

        let task = Task.detached(priority: .userInitiated) {
            var shouldNotifyCompletion = false
            var completionPreview: String?

            do {
                guard let providerConfig else {
                    throw LLMError.invalidRequest(message: "Provider not found. Configure it in Settings.")
                }

                var history = baseHistory
                if let systemPrompt, !systemPrompt.isEmpty {
                    history.insert(Message(role: .system, content: [.text(systemPrompt)]), at: 0)
                }

                // Apply message count limit first if set
                if let maxMessages = maxHistoryMessages, shouldTruncateMessages, history.count > maxMessages {
                    // Keep system messages + last N messages
                    let systemMessages = history.prefix(while: { $0.role == .system })
                    let nonSystemMessages = history.drop(while: { $0.role == .system })
                    let kept = Array(nonSystemMessages.suffix(maxMessages))
                    history = Array(systemMessages) + kept
                }

                // Then apply token-based truncation if enabled
                if shouldTruncateMessages {
                    history = ChatHistoryTruncator.truncatedHistory(
                        history,
                        contextWindow: modelContextWindow,
                        reservedOutputTokens: reservedOutputTokens
                    )
                }

                let providerManager = ProviderManager()
                let adapter = try await providerManager.createAdapter(for: providerConfig)
                let (mcpTools, mcpRoutes) = try await MCPHub.shared.toolDefinitions(for: mcpServerConfigs)
                let (builtinTools, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
                    for: controlsToUse,
                    useBuiltinSearch: shouldOfferBuiltinSearch
                )
                let allTools = mcpTools + builtinTools
                let providerType = providerConfig.type

                var requestControls = controlsToUse
                let optimizedContextCache = await ContextCacheUtilities.applyAutomaticContextCacheOptimizations(
                    adapter: adapter,
                    providerType: providerType,
                    modelID: modelID,
                    messages: history,
                    controls: requestControls,
                    tools: allTools
                )
                history = optimizedContextCache.messages
                requestControls = optimizedContextCache.controls

                var iteration = 0
                let maxToolIterations = 8

                while iteration < maxToolIterations {
                    try Task.checkCancellation()

                    var assistantPartRefs: [StreamedAssistantPartRef] = []
                    var assistantTextSegments: [String] = []
                    var assistantImageSegments: [ImageContent] = []
                    var assistantVideoSegments: [VideoContent] = []
                    var assistantThinkingSegments: [ThinkingBlockAccumulator] = []
                    var toolCallsByID: [String: ToolCall] = [:]
                    var toolCallOrder: [String] = []
                    var searchActivitiesByID: [String: SearchActivity] = [:]
                    var searchActivityOrder: [String] = []

                    func appendAssistantTextDelta(_ delta: String) {
                        guard !delta.isEmpty else { return }
                        if let last = assistantPartRefs.last, case .text(let idx) = last {
                            assistantTextSegments[idx].append(delta)
                        } else {
                            let idx = assistantTextSegments.count
                            assistantTextSegments.append(delta)
                            assistantPartRefs.append(.text(idx))
                        }
                    }

                    func appendAssistantImage(_ image: ImageContent) {
                        let idx = assistantImageSegments.count
                        assistantImageSegments.append(image)
                        assistantPartRefs.append(.image(idx))
                    }

                    func appendAssistantVideo(_ video: VideoContent) {
                        let idx = assistantVideoSegments.count
                        assistantVideoSegments.append(video)
                        assistantPartRefs.append(.video(idx))
                    }

                    func appendAssistantThinkingDelta(_ delta: ThinkingDelta) {
                        switch delta {
                        case .thinking(let textDelta, let signature):
                            if textDelta.isEmpty,
                               let signature,
                               let last = assistantPartRefs.last,
                               case .thinking(let idx) = last {
                                if assistantThinkingSegments[idx].signature != signature {
                                    assistantThinkingSegments[idx].signature = signature
                                }
                                return
                            }

                            if let last = assistantPartRefs.last,
                               case .thinking(let idx) = last,
                               assistantThinkingSegments[idx].signature == signature {
                                if !textDelta.isEmpty {
                                    assistantThinkingSegments[idx].text.append(textDelta)
                                }
                                return
                            }

                            let idx = assistantThinkingSegments.count
                            assistantThinkingSegments.append(
                                ThinkingBlockAccumulator(text: textDelta, signature: signature)
                            )
                            assistantPartRefs.append(.thinking(idx))

                        case .redacted(let data):
                            assistantPartRefs.append(.redacted(RedactedThinkingBlock(data: data)))
                        }
                    }

                    func upsertSearchActivity(_ activity: SearchActivity) {
                        if let existing = searchActivitiesByID[activity.id] {
                            searchActivitiesByID[activity.id] = existing.merged(with: activity)
                        } else {
                            searchActivityOrder.append(activity.id)
                            searchActivitiesByID[activity.id] = activity
                        }
                    }

                    func upsertToolCall(_ call: ToolCall) {
                        if toolCallsByID[call.id] == nil {
                            toolCallOrder.append(call.id)
                            toolCallsByID[call.id] = call
                            return
                        }

                        let existing = toolCallsByID[call.id]
                        let mergedArguments = (existing?.arguments ?? [:]).merging(call.arguments) { _, newValue in newValue }
                        let mergedSignature = call.signature ?? existing?.signature
                        let mergedName = call.name.isEmpty ? (existing?.name ?? call.name) : call.name
                        toolCallsByID[call.id] = ToolCall(
                            id: call.id,
                            name: mergedName,
                            arguments: mergedArguments,
                            signature: mergedSignature
                        )
                    }

                    func buildAssistantParts() -> [ContentPart] {
                        var parts: [ContentPart] = []
                        parts.reserveCapacity(assistantPartRefs.count)

                        for ref in assistantPartRefs {
                            switch ref {
                            case .text(let idx):
                                parts.append(.text(assistantTextSegments[idx]))
                            case .image(let idx):
                                parts.append(.image(assistantImageSegments[idx]))
                            case .video(let idx):
                                parts.append(.video(assistantVideoSegments[idx]))
                            case .thinking(let idx):
                                let thinking = assistantThinkingSegments[idx]
                                parts.append(.thinking(ThinkingBlock(text: thinking.text, signature: thinking.signature)))
                            case .redacted(let redacted):
                                parts.append(.redactedThinking(redacted))
                            }
                        }

                        return parts
                    }

                    func buildSearchActivities() -> [SearchActivity] {
                        searchActivityOrder.compactMap { searchActivitiesByID[$0] }
                    }

                    func buildToolCalls() -> [ToolCall] {
                        toolCallOrder.compactMap { toolCallsByID[$0] }
                    }

                    await MainActor.run {
                        streamingState.reset()
                    }

                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: modelID,
                        controls: requestControls,
                        tools: allTools,
                        streaming: true
                    )

                    // Streaming can yield very frequent deltas. Throttle how often we publish changes
                    // to SwiftUI to avoid re-layout/scrolling on every token.
                    var lastUIFlushUptime: TimeInterval = 0
                    var pendingTextDelta = ""
                    var pendingThinkingDelta = ""
                    var streamedCharacterCount = 0

                    func uiFlushInterval() -> TimeInterval {
                        switch streamedCharacterCount {
                        case 0..<4_000:
                            return 0.08
                        case 4_000..<12_000:
                            return 0.10
                        default:
                            return 0.12
                        }
                    }

                    func flushStreamingUI(force: Bool = false) async {
                        let now = ProcessInfo.processInfo.systemUptime
                        guard force || now - lastUIFlushUptime >= uiFlushInterval() else { return }
                        guard force || !pendingTextDelta.isEmpty || !pendingThinkingDelta.isEmpty else { return }

                        lastUIFlushUptime = now
                        let textDelta = pendingTextDelta
                        let thinkingDelta = pendingThinkingDelta
                        pendingTextDelta = ""
                        pendingThinkingDelta = ""

                        await MainActor.run {
                            streamingState.appendDeltas(textDelta: textDelta, thinkingDelta: thinkingDelta)
                        }
                    }

                    for try await event in stream {
                        try Task.checkCancellation()

                        switch event {
                        case .messageStart:
                            break
                        case .contentDelta(let part):
                            if case .text(let delta) = part {
                                appendAssistantTextDelta(delta)
                                pendingTextDelta.append(delta)
                                streamedCharacterCount += delta.count
                            } else if case .image(let image) = part {
                                appendAssistantImage(image)
                            } else if case .video(let video) = part {
                                appendAssistantVideo(video)
                            }
                        case .thinkingDelta(let delta):
                            appendAssistantThinkingDelta(delta)
                            switch delta {
                            case .thinking(let textDelta, _):
                                if !textDelta.isEmpty {
                                    pendingThinkingDelta.append(textDelta)
                                    streamedCharacterCount += textDelta.count
                                }
                            case .redacted:
                                break
                            }
                        case .toolCallStart(let call):
                            upsertToolCall(call)
                            if builtinRoutes.contains(functionName: call.name),
                               let searchActivity = makeSearchActivityForToolCallStart(
                                   call: call,
                                   providerOverride: builtinRoutes.provider(for: call.name)
                               ) {
                                upsertSearchActivity(searchActivity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(searchActivity)
                                }
                            }
                            let visibleToolCalls = buildToolCalls()
                            await MainActor.run {
                                streamingState.setToolCalls(visibleToolCalls)
                            }
                        case .toolCallDelta:
                            break
                        case .toolCallEnd(let call):
                            upsertToolCall(call)
                            let visibleToolCalls = buildToolCalls()
                            await MainActor.run {
                                streamingState.setToolCalls(visibleToolCalls)
                            }
                        case .searchActivity(let activity):
                            upsertSearchActivity(activity)
                            await MainActor.run {
                                streamingState.upsertSearchActivity(activity)
                            }
                        case .messageEnd:
                            break
                        case .error(let err):
                            throw err
                        }

                        await flushStreamingUI()
                    }

                    await flushStreamingUI(force: true)

                    let toolCalls = buildToolCalls()
                    let assistantParts = buildAssistantParts()
                    let searchActivities = buildSearchActivities()
                    var persistedAssistantMessageID: UUID?
                    if !assistantParts.isEmpty || !toolCalls.isEmpty || !searchActivities.isEmpty {
                        let persistedParts = await AttachmentImportPipeline.persistImagesToDisk(assistantParts)
                        let assistantMessage = Message(
                            role: .assistant,
                            content: persistedParts,
                            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                            searchActivities: searchActivities.isEmpty ? nil : searchActivities
                        )
                        if let preview = AttachmentImportPipeline.completionNotificationPreview(from: persistedParts) {
                            completionPreview = preview
                        }

                        persistedAssistantMessageID = await MainActor.run {
                            do {
                                let entity = try MessageEntity.fromDomain(assistantMessage)
                                entity.generatedProviderID = providerID
                                entity.generatedModelID = modelID
                                entity.generatedModelName = modelNameSnapshot
                                entity.conversation = conversationEntity
                                conversationEntity.messages.append(entity)
                                conversationEntity.updatedAt = Date()
                                rebuildMessageCaches()
                                try? modelContext.save()
                                // Preserve the assistant bubble so search timeline updates can be merged after tool results.
                                return entity.id
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                                return nil
                            }
                        }

                        // End streaming atomically with assistant message persistence
                        // to prevent the brief duplicate message flash.
                        if toolCalls.isEmpty {
                            await MainActor.run {
                                streamingStore.endSession(conversationID: conversationID)
                            }
                        }

                        history.append(assistantMessage)

                        if triggeredByUserSend,
                           toolCalls.isEmpty,
                           let target = chatNamingTarget {
                            await maybeAutoRenameConversation(
                                targetProvider: target.provider,
                                targetModelID: target.modelID,
                                history: history,
                                finalAssistantMessage: assistantMessage
                            )
                        }
                    }

                    guard !toolCalls.isEmpty else {
                        shouldNotifyCompletion = !assistantParts.isEmpty
                        break
                    }

                    await MainActor.run {
                        streamingState.reset()
                        streamingState.setToolCalls(toolCalls)
                    }

                    var toolResults: [ToolResult] = []
                    var toolOutputLines: [String] = []
                    var toolSearchActivitiesByID: [String: SearchActivity] = [:]
                    var toolSearchActivityOrder: [String] = []

                    func upsertToolSearchActivity(_ activity: SearchActivity) {
                        if let existing = toolSearchActivitiesByID[activity.id] {
                            toolSearchActivitiesByID[activity.id] = existing.merged(with: activity)
                        } else {
                            toolSearchActivityOrder.append(activity.id)
                            toolSearchActivitiesByID[activity.id] = activity
                        }
                    }

                    for call in toolCalls {
                        let callStart = Date()
                        do {
                            let result: MCPToolCallResult
                            if builtinRoutes.contains(functionName: call.name) {
                                result = try await BuiltinSearchToolHub.shared.executeTool(
                                    functionName: call.name,
                                    arguments: call.arguments,
                                    routes: builtinRoutes
                                )
                            } else {
                                result = try await MCPHub.shared.executeTool(
                                    functionName: call.name,
                                    arguments: call.arguments,
                                    routes: mcpRoutes
                                )
                            }
                            let duration = Date().timeIntervalSince(callStart)
                            let normalizedContent = normalizedToolResultContent(
                                result.text,
                                toolName: call.name,
                                isError: result.isError
                            )
                            let toolResult = ToolResult(
                                toolCallID: call.id,
                                toolName: call.name,
                                content: normalizedContent,
                                isError: result.isError,
                                signature: call.signature,
                                durationSeconds: duration
                            )
                            toolResults.append(toolResult)
                            await MainActor.run {
                                streamingState.upsertToolResult(toolResult)
                            }

                            if result.isError {
                                toolOutputLines.append("Tool \(call.name) failed:\n\(normalizedContent)")
                            } else {
                                toolOutputLines.append("Tool \(call.name):\n\(normalizedContent)")
                            }

                            if let activity = makeSearchActivityFromToolResult(
                                call: call,
                                toolResultText: result.text,
                                isError: result.isError,
                                providerOverride: builtinRoutes.provider(for: call.name)
                            ) {
                                upsertToolSearchActivity(activity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(activity)
                                }
                            }
                        } catch {
                            let duration = Date().timeIntervalSince(callStart)
                            let normalizedError = normalizedToolResultContent(
                                error.localizedDescription,
                                toolName: call.name,
                                isError: true
                            )
                            let llmErrorContent = "Tool execution failed: \(normalizedError). You may retry this tool call with corrected arguments."
                            let toolResult = ToolResult(
                                toolCallID: call.id,
                                toolName: call.name,
                                content: llmErrorContent,
                                isError: true,
                                signature: call.signature,
                                durationSeconds: duration
                            )
                            toolResults.append(toolResult)
                            await MainActor.run {
                                streamingState.upsertToolResult(toolResult)
                            }
                            toolOutputLines.append("Tool \(call.name) failed:\n\(llmErrorContent)")

                            if let activity = makeSearchActivityFromToolResult(
                                call: call,
                                toolResultText: llmErrorContent,
                                isError: true,
                                providerOverride: builtinRoutes.provider(for: call.name)
                            ) {
                                upsertToolSearchActivity(activity)
                                await MainActor.run {
                                    streamingState.upsertSearchActivity(activity)
                                }
                            }
                        }
                    }

                    let toolSearchActivities = toolSearchActivityOrder.compactMap { toolSearchActivitiesByID[$0] }
                    if let assistantMessageID = persistedAssistantMessageID, !toolSearchActivities.isEmpty {
                        await MainActor.run {
                            mergeSearchActivitiesIntoAssistantMessage(
                                messageID: assistantMessageID,
                                newActivities: toolSearchActivities
                            )
                        }
                    }

                    let toolMessage = Message(
                        role: .tool,
                        content: toolOutputLines.isEmpty ? [] : [.text(toolOutputLines.joined(separator: "\n\n"))],
                        toolResults: toolResults,
                        searchActivities: toolSearchActivities.isEmpty ? nil : toolSearchActivities
                    )
                    await MainActor.run {
                        do {
                            let entity = try MessageEntity.fromDomain(toolMessage)
                            entity.conversation = conversationEntity
                            conversationEntity.messages.append(entity)
                            conversationEntity.updatedAt = Date()
                            rebuildMessageCaches()
                            try? modelContext.save()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    history.append(toolMessage)
                    iteration += 1
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            let shouldNotifyNow = shouldNotifyCompletion
            let previewForNotification = completionPreview
            await MainActor.run {
                if shouldNotifyNow {
                    responseCompletionNotifier.notifyCompletionIfNeeded(
                        conversationID: conversationID,
                        conversationTitle: conversationEntity.title,
                        replyPreview: previewForNotification
                    )
                }
                streamingStore.endSession(conversationID: conversationID)
            }
        }
        streamingStore.attachTask(task, conversationID: conversationID)
    }

    private var isChatNamingPluginEnabled: Bool {
        AppPreferences.isPluginEnabled("chat_naming")
    }

    private var chatNamingMode: ChatNamingMode {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: AppPreferenceKeys.chatNamingMode) ?? ChatNamingMode.firstRoundFixed.rawValue
        return ChatNamingMode(rawValue: raw) ?? .firstRoundFixed
    }

    @MainActor
    private func resolvedChatNamingTarget() -> (provider: ProviderConfig, modelID: String)? {
        guard isChatNamingPluginEnabled else { return nil }

        let defaults = UserDefaults.standard
        let providerID = (defaults.string(forKey: AppPreferenceKeys.chatNamingProviderID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = (defaults.string(forKey: AppPreferenceKeys.chatNamingModelID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        guard let providerEntity = providers.first(where: { $0.id == providerID }),
              let provider = try? providerEntity.toDomain() else {
            return nil
        }

        let models = providerEntity.enabledModels
        guard models.contains(where: { $0.id == modelID }) else { return nil }

        return (provider, modelID)
    }

    @MainActor
    private func maybeAutoRenameConversation(
        targetProvider: ProviderConfig,
        targetModelID: String,
        history: [Message],
        finalAssistantMessage: Message
    ) async {
        guard let latestUser = history.last(where: { $0.role == .user }) else { return }

        if chatNamingMode == .firstRoundFixed {
            let current = conversationEntity.title
            if current != "New Chat" {
                return
            }
        }

        do {
            let title = try await conversationTitleGenerator.generateTitle(
                providerConfig: targetProvider,
                modelID: targetModelID,
                contextMessages: [latestUser, finalAssistantMessage],
                maxCharacters: 40
            )

            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 40)
            guard !normalized.isEmpty else { return }
            conversationEntity.title = normalized
            try? modelContext.save()
        } catch {
            if chatNamingMode == .firstRoundFixed {
                if conversationEntity.title == "New Chat" {
                    conversationEntity.title = fallbackTitleFromMessage(latestUser)
                    try? modelContext.save()
                }
            }
        }
    }

    private func fallbackTitleFromMessage(_ message: Message) -> String {
        let text = message.content.compactMap { part -> String? in
            switch part {
            case .text(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .file(let file):
                let base = (file.filename as NSString).deletingPathExtension
                let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .image:
                return "Image"
            case .thinking, .redactedThinking, .audio, .video:
                return nil
            }
        }.first

        guard let text else { return "New Chat" }
        return makeConversationTitle(from: text)
    }

    nonisolated private func normalizedToolResultContent(_ text: String, toolName: String, isError: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if isError {
            return "Tool \(toolName) failed without details"
        }
        return "Tool \(toolName) returned no output"
    }

    nonisolated private func makeSearchActivityForToolCallStart(
        call: ToolCall,
        providerOverride: SearchPluginProvider?
    ) -> SearchActivity? {
        guard isSearchToolName(call.name) else { return nil }

        var args: [String: AnyCodable] = [:]
        let query = (call.arguments["query"]?.value as? String)
            ?? (call.arguments["q"]?.value as? String)
            ?? ""
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            args["query"] = AnyCodable(trimmedQuery)
        }

        if let providerOverride {
            args["provider"] = AnyCodable(providerOverride.rawValue)
        }

        return SearchActivity(
            id: "tool-search-\(call.id)",
            type: "tool_web_search",
            status: .searching,
            arguments: args
        )
    }

    nonisolated private func makeSearchActivityFromToolResult(
        call: ToolCall,
        toolResultText: String,
        isError: Bool,
        providerOverride: SearchPluginProvider?
    ) -> SearchActivity? {
        guard isSearchToolName(call.name) else { return nil }

        let decoder = JSONDecoder()
        var query = ""
        var sources: [[String: Any]] = []
        var providerRaw = providerOverride?.rawValue

        if let data = toolResultText.data(using: .utf8),
           let payload = try? decoder.decode(BuiltinToolActivityPayload.self, from: data) {
            query = payload.query
            providerRaw = providerRaw ?? payload.provider.rawValue
            sources = payload.results.map { row in
                var item: [String: Any] = [
                    "url": row.url,
                    "title": row.title
                ]
                if let snippet = row.snippet {
                    item["snippet"] = snippet
                }
                if let publishedAt = row.publishedAt {
                    item["published_at"] = publishedAt
                }
                if let source = row.source {
                    item["source"] = source
                }
                return item
            }
        } else {
            query = (call.arguments["query"]?.value as? String)
                ?? (call.arguments["q"]?.value as? String)
                ?? ""
        }

        var args: [String: AnyCodable] = [:]
        if !query.isEmpty {
            args["query"] = AnyCodable(query)
        }
        if !sources.isEmpty {
            args["sources"] = AnyCodable(sources)
        }
        if let providerRaw, !providerRaw.isEmpty {
            args["provider"] = AnyCodable(providerRaw)
        }

        return SearchActivity(
            id: "tool-search-\(call.id)",
            type: "tool_web_search",
            status: isError ? .failed : .completed,
            arguments: args
        )
    }

    nonisolated private func isSearchToolName(_ toolName: String) -> Bool {
        let normalizedName = toolName.lowercased()
        return normalizedName.contains("search")
            || normalizedName.contains("web_lookup")
            || normalizedName.contains("web_search")
    }

    @MainActor
    private func mergeSearchActivitiesIntoAssistantMessage(
        messageID: UUID,
        newActivities: [SearchActivity]
    ) {
        guard !newActivities.isEmpty else { return }
        guard let entity = conversationEntity.messages.first(where: { $0.id == messageID && $0.role == "assistant" }) else {
            return
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let existingActivities: [SearchActivity]
        if let data = entity.searchActivitiesData,
           let decoded = try? decoder.decode([SearchActivity].self, from: data) {
            existingActivities = decoded
        } else {
            existingActivities = []
        }

        var order: [String] = []
        var byID: [String: SearchActivity] = [:]

        for activity in existingActivities {
            if byID[activity.id] == nil {
                order.append(activity.id)
            }
            byID[activity.id] = activity
        }

        for activity in newActivities {
            if let existing = byID[activity.id] {
                byID[activity.id] = existing.merged(with: activity)
            } else {
                order.append(activity.id)
                byID[activity.id] = activity
            }
        }

        let mergedActivities = order.compactMap { byID[$0] }
        entity.searchActivitiesData = mergedActivities.isEmpty ? nil : (try? encoder.encode(mergedActivities))
        conversationEntity.updatedAt = Date()
        rebuildMessageCaches()
        try? modelContext.save()
    }
    
    // MARK: - Model Controls (Shortened for brevity, preserving existing logic)
    
    private var providerType: ProviderType? {
        if let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
           let providerType = ProviderType(rawValue: provider.typeRaw) {
            return providerType
        }

        // Fallback: for the built-in providers, `providerID` matches the provider type.
        return ProviderType(rawValue: conversationEntity.providerID)
    }

    private var reasoningLabel: String {
        guard supportsReasoningControl else { return "Not supported" }
        guard isReasoningEnabled else { return "Off" }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return "Not supported" }

        switch reasoningType {
        case .budget:
            guard let budgetTokens = controls.reasoning?.budgetTokens else { return "On" }
            return "\(budgetTokens) tokens"
        case .effort:
            if providerType == .anthropic {
                if anthropicUsesEffortMode {
                    let effort = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort ?? .high
                    return effort == .xhigh ? "Max" : effort.displayName
                }
                let budgetTokens = controls.reasoning?.budgetTokens ?? anthropicDefaultBudgetTokens
                return "\(budgetTokens) tokens"
            }
            return controls.reasoning?.effort?.displayName ?? "On"
        case .toggle:
            return "On"
        case .none:
            return "Not supported"
        }
    }

    private var supportsReasoningSummaryControl: Bool {
        providerType == .openai || providerType == .openaiWebSocket
    }

    @ViewBuilder
    private var reasoningMenuContent: some View {
        if let reasoningConfig = selectedReasoningConfig, reasoningConfig.type != .none {
            if supportsReasoningDisableToggle {
                Button { setReasoningOff() } label: { menuItemLabel("Off", isSelected: !isReasoningEnabled) }
            }

            switch reasoningConfig.type {
            case .toggle:
                Button { setReasoningOn() } label: { menuItemLabel("On", isSelected: isReasoningEnabled) }

                if supportsCerebrasPreservedThinkingToggle {
                    Divider()
                    Toggle("Preserve thinking", isOn: cerebrasPreserveThinkingBinding)
                        .help("Keeps GLM thinking across turns (maps to clear_thinking: false).")
                }

            case .effort:
                if providerType == .anthropic {
                    Button { openThinkingBudgetEditor() } label: {
                        menuItemLabel("Configure thinking\u{2026}", isSelected: isReasoningEnabled)
                    }
                } else {
                    effortLevelButtons(for: availableReasoningEffortLevels)

                    if supportsReasoningSummaryControl {
                        Divider()
                        Text("Reasoning summary")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(ReasoningSummary.allCases, id: \.self) { summary in
                            Button {
                                setReasoningSummary(summary)
                            } label: {
                                menuItemLabel(summary.displayName, isSelected: (controls.reasoning?.summary ?? .auto) == summary)
                            }
                        }
                    }
                }

                if supportsFireworksReasoningHistoryToggle {
                    Divider()
                    Text("Thinking history")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button { setFireworksReasoningHistory(nil) } label: { menuItemLabel("Default (model)", isSelected: fireworksReasoningHistory == nil) }
                    ForEach(fireworksReasoningHistoryOptions, id: \.self) { option in
                        Button {
                            setFireworksReasoningHistory(option)
                        } label: {
                            menuItemLabel(
                                fireworksReasoningHistoryLabel(for: option),
                                isSelected: fireworksReasoningHistory == option
                            )
                        }
                    }
                }

            case .budget:
                Button { openThinkingBudgetEditor() } label: {
                    let current = controls.reasoning?.budgetTokens ?? reasoningConfig.defaultBudget ?? 1024
                    menuItemLabel("Budget tokens… (\(current))", isSelected: isReasoningEnabled)
                }

            case .none:
                EmptyView()
            }
        } else {
            Text("Not supported")
                .foregroundStyle(.secondary)
        }
    }

    private var supportsFireworksReasoningHistoryToggle: Bool {
        !fireworksReasoningHistoryOptions.isEmpty
    }

    private var fireworksReasoningHistoryOptions: [String] {
        guard providerType == .fireworks else { return [] }
        if isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            return ["interleaved", "disabled"]
        }
        if isFireworksModelID(conversationEntity.modelID, canonicalID: "kimi-k2p5")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-4p7")
            || isFireworksModelID(conversationEntity.modelID, canonicalID: "glm-5") {
            return ["preserved", "interleaved", "disabled"]
        }
        return []
    }

    private var fireworksReasoningHistory: String? {
        controls.providerSpecific["reasoning_history"]?.value as? String
    }

    private func setFireworksReasoningHistory(_ value: String?) {
        if let value {
            controls.providerSpecific["reasoning_history"] = AnyCodable(value)
        } else {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
        persistControlsToConversation()
    }

    private func isFireworksModelID(_ modelID: String, canonicalID: String) -> Bool {
        fireworksCanonicalModelID(modelID) == canonicalID
    }

    private func isFireworksMiniMaxM2FamilyModel(_ modelID: String) -> Bool {
        guard let canonicalID = fireworksCanonicalModelID(modelID) else { return false }
        return Self.fireworksMiniMaxM2CanonicalModelIDs.contains(canonicalID)
    }

    private func fireworksCanonicalModelID(_ modelID: String) -> String? {
        let lower = modelID.lowercased()
        if lower.hasPrefix("fireworks/") {
            return String(lower.dropFirst("fireworks/".count))
        }
        if lower.hasPrefix("accounts/fireworks/models/") {
            return String(lower.dropFirst("accounts/fireworks/models/".count))
        }
        // Compatibility for legacy persisted IDs stored without provider prefixes.
        if !lower.contains("/") {
            return lower
        }
        return nil
    }

    private func fireworksReasoningHistoryLabel(for option: String) -> String {
        switch option {
        case "preserved":
            return "Preserved"
        case "interleaved":
            return "Interleaved"
        case "disabled":
            return "Disabled"
        default:
            return option
        }
    }

    private var supportsCerebrasPreservedThinkingToggle: Bool {
        guard providerType == .cerebras else { return false }
        return conversationEntity.modelID.lowercased() == "zai-glm-4.7"
    }

    private var cerebrasPreserveThinkingBinding: Binding<Bool> {
        Binding(
            get: {
                // Cerebras `clear_thinking` defaults to true. Preserve thinking == clear_thinking false.
                let clear = (controls.providerSpecific["clear_thinking"]?.value as? Bool) ?? true
                return clear == false
            },
            set: { preserve in
                if preserve {
                    controls.providerSpecific["clear_thinking"] = AnyCodable(false)
                } else {
                    // Use provider default (clear_thinking true).
                    controls.providerSpecific.removeValue(forKey: "clear_thinking")
                }
                persistControlsToConversation()
            }
        )
    }

    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var availableReasoningEffortLevels: [ReasoningEffort] {
        ModelCapabilityRegistry.supportedReasoningEfforts(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    @ViewBuilder
    private func effortLevelButtons(for levels: [ReasoningEffort]) -> some View {
        ForEach(levels, id: \.self) { level in
            Button { setReasoningEffort(level) } label: {
                menuItemLabel(
                    level == .xhigh ? "Extreme" : level.displayName,
                    isSelected: isReasoningEnabled && controls.reasoning?.effort == level
                )
            }
        }
    }

    private var webSearchEnabledBinding: Binding<Bool> {
        Binding(
            get: {
                if providerType == .perplexity {
                    return controls.webSearch?.enabled ?? true
                }
                return controls.webSearch?.enabled ?? false
            },
            set: { enabled in
                if controls.webSearch == nil {
                    controls.webSearch = defaultWebSearchControls(enabled: enabled)
                } else {
                    controls.webSearch?.enabled = enabled
                    ensureValidWebSearchDefaultsIfEnabled()
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    private var webSearchMenuContent: some View {
        Toggle("Web Search", isOn: webSearchEnabledBinding)
        if isWebSearchEnabled {
            if supportsSearchEngineModeSwitch {
                Divider()
                Menu("Engine") {
                    Button {
                        setSearchEnginePreference(useJinSearch: false)
                    } label: {
                        menuItemLabel("Native", isSelected: !usesBuiltinSearchPlugin)
                    }

                    Button {
                        setSearchEnginePreference(useJinSearch: true)
                    } label: {
                        menuItemLabel("Jin Search", isSelected: usesBuiltinSearchPlugin)
                    }
                }
            }

            if usesBuiltinSearchPlugin {
                Divider()
                Menu("Provider") {
                    ForEach(SearchPluginProvider.allCases) { provider in
                        Button {
                            if controls.searchPlugin == nil {
                                controls.searchPlugin = SearchPluginControls()
                            }
                            controls.searchPlugin?.provider = provider
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel(
                                provider.displayName,
                                isSelected: effectiveSearchPluginProvider == provider
                            )
                        }
                    }
                }

                Menu("Max Results") {
                    let current = controls.searchPlugin?.maxResults ?? WebSearchPluginSettingsStore.load().defaultMaxResults
                    ForEach([3, 5, 8, 10, 20, 30, 50], id: \.self) { value in
                        Button {
                            if controls.searchPlugin == nil {
                                controls.searchPlugin = SearchPluginControls()
                            }
                            controls.searchPlugin?.maxResults = value
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel("\(value)", isSelected: current == value)
                        }
                    }
                }

                Menu("Recency") {
                    let current = controls.searchPlugin?.recencyDays
                    Button {
                        if controls.searchPlugin == nil {
                            controls.searchPlugin = SearchPluginControls()
                        }
                        controls.searchPlugin?.recencyDays = nil
                        persistControlsToConversation()
                    } label: {
                        menuItemLabel("Any time", isSelected: current == nil)
                    }

                    ForEach([1, 7, 30, 90], id: \.self) { value in
                        Button {
                            if controls.searchPlugin == nil {
                                controls.searchPlugin = SearchPluginControls()
                            }
                            controls.searchPlugin?.recencyDays = value
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel("Past \(value)d", isSelected: current == value)
                        }
                    }
                }

                Divider()
                Toggle("Include raw snippets", isOn: builtinSearchIncludeRawBinding)

                if effectiveSearchPluginProvider == .jina {
                    Toggle("Fetch pages via Reader", isOn: builtinSearchFetchPageBinding)
                } else if effectiveSearchPluginProvider == .exa {
                    Toggle("Exa autoprompt", isOn: builtinSearchExaAutopromptBinding)
                } else if effectiveSearchPluginProvider == .firecrawl {
                    Toggle("Extract markdown", isOn: builtinSearchFirecrawlExtractBinding)
                }
            } else {
                switch providerType {
                case .openai, .openaiWebSocket:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        Button {
                            controls.webSearch?.contextSize = size
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel(size.displayName, isSelected: (controls.webSearch?.contextSize ?? .medium) == size)
                        }
                    }
                case .perplexity:
                    Divider()
                    ForEach(WebSearchContextSize.allCases, id: \.self) { size in
                        Button {
                            if controls.webSearch == nil {
                                controls.webSearch = defaultWebSearchControls(enabled: true)
                            }
                            controls.webSearch?.contextSize = size
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel(size.displayName, isSelected: (controls.webSearch?.contextSize ?? .low) == size)
                        }
                    }
                case .xai:
                    Divider()
                    Toggle("Web", isOn: webSearchSourceBinding(.web))
                    Toggle("X", isOn: webSearchSourceBinding(.x))

                    if Set(controls.webSearch?.sources ?? []).isEmpty {
                        Divider()
                        Text("Select at least one source.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .anthropic:
                    Divider()
                    Menu("Max Uses") {
                        let current = controls.webSearch?.maxUses
                        Button {
                            controls.webSearch?.maxUses = nil
                            persistControlsToConversation()
                        } label: {
                            menuItemLabel("Default (10)", isSelected: current == nil)
                        }
                        ForEach([1, 3, 5, 10, 20], id: \.self) { value in
                            Button {
                                controls.webSearch?.maxUses = value
                                persistControlsToConversation()
                            } label: {
                                menuItemLabel("\(value)", isSelected: current == value)
                            }
                        }
                    }
                    if supportsAnthropicDynamicFiltering {
                        Toggle("Dynamic Filtering", isOn: Binding(
                            get: { controls.webSearch?.dynamicFiltering ?? false },
                            set: { newValue in
                                controls.webSearch?.dynamicFiltering = newValue ? true : nil
                                persistControlsToConversation()
                            }
                        ))
                    }
                    Divider()
                    Button("Configure\u{2026}") {
                        openAnthropicWebSearchEditor()
                    }
                case .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
                    EmptyView()
                }
            }
        }
    }

    private func setSearchEnginePreference(useJinSearch: Bool) {
        if controls.searchPlugin == nil {
            controls.searchPlugin = SearchPluginControls()
        }
        controls.searchPlugin?.preferJinSearch = useJinSearch
        persistControlsToConversation()
    }

    @ViewBuilder
    private var contextCacheMenuContent: some View {
        Button {
            controls.contextCache = ContextCacheControls(mode: .off)
            persistControlsToConversation()
        } label: {
            menuItemLabel("Off", isSelected: effectiveContextCacheMode == .off)
        }

        Button {
            var cache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
            cache.mode = .implicit
            if providerType != .anthropic {
                cache.strategy = nil
            }
            if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
                cache.cacheKey = nil
            }
            if providerType != .xai {
                cache.minTokensThreshold = nil
            }
            if providerType != .xai {
                cache.conversationID = nil
            }
            if providerType != .gemini && providerType != .vertexai {
                cache.cachedContentName = nil
            }
            controls.contextCache = cache
            persistControlsToConversation()
        } label: {
            menuItemLabel("Implicit", isSelected: effectiveContextCacheMode == .implicit)
        }

        if supportsExplicitContextCacheMode {
            Button {
                var cache = controls.contextCache ?? ContextCacheControls(mode: .explicit)
                cache.mode = .explicit
                controls.contextCache = cache
                persistControlsToConversation()
            } label: {
                menuItemLabel("Explicit", isSelected: effectiveContextCacheMode == .explicit)
            }
        }

        Divider()

        Button("Configure…") {
            openContextCacheEditor()
        }

        if controls.contextCache != nil {
            Divider()
            Button("Reset", role: .destructive) {
                controls.contextCache = nil
                persistControlsToConversation()
            }
        }
    }

    private var mcpToolsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.mcpTools?.enabled == true },
            set: { enabled in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: enabled)
                } else {
                    controls.mcpTools?.enabled = enabled
                }
                persistControlsToConversation()
            }
        )
    }

    @ViewBuilder
    private var mcpToolsMenuContent: some View {
        Toggle("MCP Tools", isOn: mcpToolsEnabledBinding)

        if isMCPToolsEnabled {
            if eligibleMCPServers.isEmpty {
                Divider()
                Text("No MCP servers enabled for automatic tool use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                Text("Servers")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(eligibleMCPServers, id: \.id) { server in
                    Toggle(server.name, isOn: mcpServerSelectionBinding(serverID: server.id))
                }

                if selectedMCPServerIDs.isEmpty {
                    Divider()
                    Text("Select at least one server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if controls.mcpTools?.enabledServerIDs != nil {
                    Divider()
                    Button("Use all servers") {
                        resetMCPServerSelection()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imageGenerationMenuContent: some View {
        if providerType == .xai {
            Text("xAI Image")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Menu("Count") {
                Button { updateXAIImageGeneration { $0.count = nil } } label: {
                    menuItemLabel("Default", isSelected: controls.xaiImageGeneration?.count == nil)
                }
                ForEach([1, 2, 4], id: \.self) { count in
                    Button { updateXAIImageGeneration { $0.count = count } } label: {
                        menuItemLabel("\(count)", isSelected: (controls.xaiImageGeneration?.count ?? 1) == count)
                    }
                }
            }

            Menu("Aspect ratio") {
                Button { updateXAIImageGeneration { $0.aspectRatio = nil } } label: {
                    let selected = controls.xaiImageGeneration?.aspectRatio == nil
                        && controls.xaiImageGeneration?.size == nil
                    menuItemLabel("Default", isSelected: selected)
                }
                ForEach(XAIAspectRatio.allCases, id: \.self) { ratio in
                    Button {
                        updateXAIImageGeneration {
                            $0.aspectRatio = ratio
                            $0.size = nil // legacy fallback only
                        }
                    } label: {
                        menuItemLabel(
                            ratio.displayName,
                            isSelected: (controls.xaiImageGeneration?.aspectRatio ?? controls.xaiImageGeneration?.size?.mappedAspectRatio) == ratio
                        )
                    }
                }
            }

            if isImageGenerationConfigured {
                Divider()
                Button("Reset", role: .destructive) {
                    controls.xaiImageGeneration = nil
                    persistControlsToConversation()
                }
            }
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

    private func updateXAIImageGeneration(_ mutate: (inout XAIImageGenerationControls) -> Void) {
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
    private var videoGenerationMenuContent: some View {
        switch providerType {
        case .gemini, .vertexai:
            googleVideoGenerationMenuContent
        case .xai:
            xaiVideoGenerationMenuContent
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var googleVideoGenerationMenuContent: some View {
        let isVeo3 = GoogleVideoGenerationCore.isVeo3OrLater(conversationEntity.modelID)
        let isVertexProvider = providerType == .vertexai

        Text("Google Veo")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button { updateGoogleVideoGeneration { $0.durationSeconds = nil } } label: {
                menuItemLabel("Default", isSelected: controls.googleVideoGeneration?.durationSeconds == nil)
            }
            ForEach([4, 6, 8], id: \.self) { seconds in
                Button { updateGoogleVideoGeneration { $0.durationSeconds = seconds } } label: {
                    menuItemLabel("\(seconds)s", isSelected: controls.googleVideoGeneration?.durationSeconds == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button { updateGoogleVideoGeneration { $0.aspectRatio = nil } } label: {
                menuItemLabel("Default (16:9)", isSelected: controls.googleVideoGeneration?.aspectRatio == nil)
            }
            ForEach(GoogleVideoAspectRatio.allCases, id: \.self) { ratio in
                Button { updateGoogleVideoGeneration { $0.aspectRatio = ratio } } label: {
                    menuItemLabel(ratio.displayName, isSelected: controls.googleVideoGeneration?.aspectRatio == ratio)
                }
            }
        }

        if isVeo3 {
            Menu("Resolution") {
                Button { updateGoogleVideoGeneration { $0.resolution = nil } } label: {
                    menuItemLabel("Default (720p)", isSelected: controls.googleVideoGeneration?.resolution == nil)
                }
                ForEach(GoogleVideoResolution.allCases, id: \.self) { res in
                    Button { updateGoogleVideoGeneration { $0.resolution = res } } label: {
                        menuItemLabel(res.displayName, isSelected: controls.googleVideoGeneration?.resolution == res)
                    }
                }
            }
        }

        Menu("Person generation") {
            Button { updateGoogleVideoGeneration { $0.personGeneration = nil } } label: {
                menuItemLabel("Default", isSelected: controls.googleVideoGeneration?.personGeneration == nil)
            }
            ForEach(GoogleVideoPersonGeneration.allCases, id: \.self) { person in
                Button { updateGoogleVideoGeneration { $0.personGeneration = person } } label: {
                    menuItemLabel(person.displayName, isSelected: controls.googleVideoGeneration?.personGeneration == person)
                }
            }
        }

        // generateAudio is only a valid parameter for Vertex AI Veo 3 models.
        // Gemini API Veo 3+ models generate audio natively by default.
        if isVertexProvider, isVeo3 {
            Toggle(
                "Generate audio",
                isOn: Binding(
                    get: { controls.googleVideoGeneration?.generateAudio ?? false },
                    set: { newValue in
                        updateGoogleVideoGeneration { $0.generateAudio = newValue ? true : nil }
                    }
                )
            )
        }

        if isVideoGenerationConfigured {
            Divider()
            Button("Reset", role: .destructive) {
                controls.googleVideoGeneration = nil
                persistControlsToConversation()
            }
        }
    }

    @ViewBuilder
    private var xaiVideoGenerationMenuContent: some View {
        Text("xAI Video")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Menu("Duration") {
            Button { updateXAIVideoGeneration { $0.duration = nil } } label: {
                menuItemLabel("Default", isSelected: controls.xaiVideoGeneration?.duration == nil)
            }
            ForEach([3, 5, 8, 10, 15], id: \.self) { seconds in
                Button { updateXAIVideoGeneration { $0.duration = seconds } } label: {
                    menuItemLabel("\(seconds)s", isSelected: controls.xaiVideoGeneration?.duration == seconds)
                }
            }
        }

        Menu("Aspect ratio") {
            Button { updateXAIVideoGeneration { $0.aspectRatio = nil } } label: {
                menuItemLabel("Default (16:9)", isSelected: controls.xaiVideoGeneration?.aspectRatio == nil)
            }
            ForEach(
                [XAIAspectRatio.ratio1x1, .ratio16x9, .ratio9x16, .ratio4x3, .ratio3x4, .ratio3x2, .ratio2x3],
                id: \.self
            ) { ratio in
                Button { updateXAIVideoGeneration { $0.aspectRatio = ratio } } label: {
                    menuItemLabel(ratio.displayName, isSelected: controls.xaiVideoGeneration?.aspectRatio == ratio)
                }
            }
        }

        Menu("Resolution") {
            Button { updateXAIVideoGeneration { $0.resolution = nil } } label: {
                menuItemLabel("Default (480p)", isSelected: controls.xaiVideoGeneration?.resolution == nil)
            }
            ForEach(XAIVideoResolution.allCases, id: \.self) { res in
                Button { updateXAIVideoGeneration { $0.resolution = res } } label: {
                    menuItemLabel(res.displayName, isSelected: controls.xaiVideoGeneration?.resolution == res)
                }
            }
        }

        if isVideoGenerationConfigured {
            Divider()
            Button("Reset", role: .destructive) {
                controls.xaiVideoGeneration = nil
                persistControlsToConversation()
            }
        }
    }

    private func updateXAIVideoGeneration(_ mutate: (inout XAIVideoGenerationControls) -> Void) {
        var draft = controls.xaiVideoGeneration ?? XAIVideoGenerationControls()
        mutate(&draft)
        controls.xaiVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    private func updateGoogleVideoGeneration(_ mutate: (inout GoogleVideoGenerationControls) -> Void) {
        var draft = controls.googleVideoGeneration ?? GoogleVideoGenerationControls()
        mutate(&draft)
        controls.googleVideoGeneration = draft.isEmpty ? nil : draft
        persistControlsToConversation()
    }

    private func openImageGenerationEditor() {
        let current = controls.imageGeneration ?? ImageGenerationControls()
        imageGenerationDraft = current
        imageGenerationSeedDraft = current.seed.map(String.init) ?? ""
        imageGenerationCompressionQualityDraft = current.vertexCompressionQuality.map(String.init) ?? ""
        imageGenerationDraftError = nil
        showingImageGenerationSheet = true
    }

    private var isImageGenerationDraftValid: Bool {
        let seedText = imageGenerationSeedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seedText.isEmpty, Int(seedText) == nil {
            return false
        }

        let qualityText = imageGenerationCompressionQualityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qualityText.isEmpty {
            guard let quality = Int(qualityText), (0...100).contains(quality) else {
                return false
            }
        }

        return true
    }

    @discardableResult
    private func applyImageGenerationDraft() -> Bool {
        var draft = imageGenerationDraft

        let seedText = imageGenerationSeedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if seedText.isEmpty {
            draft.seed = nil
        } else if let seed = Int(seedText) {
            draft.seed = seed
        } else {
            imageGenerationDraftError = "Seed must be an integer."
            return false
        }

        let qualityText = imageGenerationCompressionQualityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if qualityText.isEmpty {
            draft.vertexCompressionQuality = nil
        } else if let quality = Int(qualityText), (0...100).contains(quality) {
            draft.vertexCompressionQuality = quality
        } else {
            imageGenerationDraftError = "JPEG quality must be an integer between 0 and 100."
            return false
        }

        if !supportsCurrentModelImageSizeControl {
            draft.imageSize = nil
        }

        if providerType != .vertexai {
            draft.vertexPersonGeneration = nil
            draft.vertexOutputMIMEType = nil
            draft.vertexCompressionQuality = nil
        }

        if draft.isEmpty {
            controls.imageGeneration = nil
        } else {
            controls.imageGeneration = draft
        }

        persistControlsToConversation()
        imageGenerationDraftError = nil
        return true
    }

    private func openContextCacheEditor() {
        let defaultMode: ContextCacheMode = (providerType == .anthropic) ? .implicit : .off
        contextCacheDraft = controls.contextCache ?? ContextCacheControls(mode: defaultMode)
        contextCacheTTLPreset = ContextCacheTTLPreset.from(ttl: contextCacheDraft.ttl)
        if case .customSeconds(let seconds) = contextCacheDraft.ttl {
            contextCacheCustomTTLDraft = "\(seconds)"
        } else {
            contextCacheCustomTTLDraft = ""
        }
        contextCacheMinTokensDraft = contextCacheDraft.minTokensThreshold.map(String.init) ?? ""
        contextCacheAdvancedExpanded = shouldExpandContextCacheAdvancedOptions(for: contextCacheDraft)
        contextCacheDraftError = nil
        showingContextCacheSheet = true
    }

    // MARK: - Anthropic Web Search Helpers

    private var supportsAnthropicDynamicFiltering: Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerType,
            modelID: conversationEntity.modelID
        )
    }

    private func normalizeAnthropicDomainFilters() {
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.blockedDomains)

        if !allowed.isEmpty {
            controls.webSearch?.allowedDomains = allowed
            controls.webSearch?.blockedDomains = nil
        } else if !blocked.isEmpty {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = blocked
        } else {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        }
    }

    private func openAnthropicWebSearchEditor() {
        let ws = controls.webSearch
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(ws?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(ws?.blockedDomains)

        anthropicWebSearchAllowedDomainsDraft = allowed.joined(separator: "\n")
        anthropicWebSearchBlockedDomainsDraft = blocked.joined(separator: "\n")

        if anthropicWebSearchDomainMode == .blocked, !blocked.isEmpty {
            anthropicWebSearchDomainMode = .blocked
        } else if !allowed.isEmpty {
            anthropicWebSearchDomainMode = .allowed
        } else if !blocked.isEmpty {
            anthropicWebSearchDomainMode = .blocked
        } else {
            anthropicWebSearchDomainMode = .none
        }
        anthropicWebSearchLocationDraft = ws?.userLocation ?? WebSearchUserLocation()
        anthropicWebSearchDraftError = nil
        showingAnthropicWebSearchSheet = true
    }

    private func applyAnthropicWebSearchDraft() {
        let allowedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicWebSearchDomainUtils.splitInput(anthropicWebSearchAllowedDomainsDraft)
        )
        let blockedDomains = AnthropicWebSearchDomainUtils.normalizedDomains(
            AnthropicWebSearchDomainUtils.splitInput(anthropicWebSearchBlockedDomainsDraft)
        )

        switch anthropicWebSearchDomainMode {
        case .none:
            anthropicWebSearchDraftError = nil
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        case .allowed:
            if allowedDomains.isEmpty {
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = nil
            } else {
                if let validationError = AnthropicWebSearchDomainUtils.firstValidationError(in: allowedDomains) {
                    anthropicWebSearchDraftError = validationError
                    return
                }
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = allowedDomains
                controls.webSearch?.blockedDomains = nil
            }
        case .blocked:
            if blockedDomains.isEmpty {
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = nil
            } else {
                if let validationError = AnthropicWebSearchDomainUtils.firstValidationError(in: blockedDomains) {
                    anthropicWebSearchDraftError = validationError
                    return
                }
                anthropicWebSearchDraftError = nil
                controls.webSearch?.allowedDomains = nil
                controls.webSearch?.blockedDomains = blockedDomains
            }
        }
        normalizeAnthropicDomainFilters()

        let loc = anthropicWebSearchLocationDraft
        controls.webSearch?.userLocation = loc.isEmpty ? nil : loc

        persistControlsToConversation()
        showingAnthropicWebSearchSheet = false
    }

    private func shouldExpandContextCacheAdvancedOptions(for draft: ContextCacheControls) -> Bool {
        guard draft.mode != .off else { return false }

        if supportsContextCacheTTL,
           let ttl = draft.ttl,
           ttl != .providerDefault {
            return true
        }

        if providerType == .xai {
            if let cacheKey = draft.cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cacheKey.isEmpty {
                return true
            }
        }

        if providerType == .xai,
           let conversationID = draft.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conversationID.isEmpty {
            return true
        }

        return false
    }

    private var isContextCacheDraftValid: Bool {
        if contextCacheTTLPreset == .custom {
            let trimmed = contextCacheCustomTTLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(trimmed), value > 0 else { return false }
        }

        let minTokensTrimmed = contextCacheMinTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !minTokensTrimmed.isEmpty {
            guard let value = Int(minTokensTrimmed), value > 0 else { return false }
        }

        if supportsExplicitContextCacheMode, contextCacheDraft.mode == .explicit {
            let name = (contextCacheDraft.cachedContentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty
        }

        return true
    }

    @discardableResult
    private func applyContextCacheDraft() -> Bool {
        var draft = contextCacheDraft

        if supportsContextCacheTTL {
            switch contextCacheTTLPreset {
            case .providerDefault:
                draft.ttl = .providerDefault
            case .minutes5:
                draft.ttl = .minutes5
            case .hour1:
                draft.ttl = .hour1
            case .custom:
                let trimmed = contextCacheCustomTTLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Int(trimmed), value > 0 else {
                    contextCacheDraftError = "Custom TTL must be a positive integer (seconds)."
                    return false
                }
                draft.ttl = .customSeconds(value)
            }
        } else {
            draft.ttl = nil
        }

        let minTokensTrimmed = contextCacheMinTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if minTokensTrimmed.isEmpty {
            draft.minTokensThreshold = nil
        } else if let value = Int(minTokensTrimmed), value > 0 {
            draft.minTokensThreshold = value
        } else {
            contextCacheDraftError = "Min tokens threshold must be a positive integer."
            return false
        }

        draft.cacheKey = draft.cacheKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.cacheKey?.isEmpty == true {
            draft.cacheKey = nil
        }

        draft.conversationID = draft.conversationID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.conversationID?.isEmpty == true {
            draft.conversationID = nil
        }

        draft.cachedContentName = draft.cachedContentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.cachedContentName?.isEmpty == true {
            draft.cachedContentName = nil
        }

        if !supportsContextCacheStrategy {
            draft.strategy = nil
        } else if draft.strategy == nil {
            draft.strategy = .systemOnly
        }

        if !supportsExplicitContextCacheMode, draft.mode == .explicit {
            draft.mode = .implicit
        }

        if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
            draft.cacheKey = nil
        }
        if providerType != .xai {
            draft.minTokensThreshold = nil
        }
        if providerType != .xai {
            draft.conversationID = nil
        }
        if providerType != .gemini && providerType != .vertexai {
            draft.cachedContentName = nil
        }

        if draft.mode == .off {
            if providerType == .anthropic {
                controls.contextCache = ContextCacheControls(mode: .off)
            } else {
                controls.contextCache = nil
            }
        } else {
            controls.contextCache = draft
        }

        normalizeControlsForCurrentSelection()
        persistControlsToConversation()
        contextCacheDraftError = nil
        return true
    }

    private func mcpServerSelectionBinding(serverID: String) -> Binding<Bool> {
        Binding(
            get: {
                selectedMCPServerIDs.contains(serverID)
            },
            set: { isOn in
                if controls.mcpTools == nil {
                    controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
                }

                let eligibleIDs = Set(eligibleMCPServers.map(\.id))
                var selected = Set(controls.mcpTools?.enabledServerIDs ?? Array(eligibleIDs))
                if isOn {
                    selected.insert(serverID)
                } else {
                    selected.remove(serverID)
                }

                let normalized = selected.intersection(eligibleIDs)
                if normalized == eligibleIDs {
                    controls.mcpTools?.enabledServerIDs = nil
                } else {
                    controls.mcpTools?.enabledServerIDs = Array(normalized).sorted()
                }

                persistControlsToConversation()
            }
        )
    }

    private func resetMCPServerSelection() {
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        } else {
            controls.mcpTools?.enabled = true
            controls.mcpTools?.enabledServerIDs = nil
        }
        persistControlsToConversation()
    }

    private func resolvedMCPServerConfigs(for controlsToUse: GenerationControls) -> [MCPServerConfig] {
        guard supportsMCPToolsControl else { return [] }
        guard controlsToUse.mcpTools?.enabled == true else { return [] }

        let eligibleServers = mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let eligibleIDs = Set(eligibleServers.map(\.id))
        let allowlist = controlsToUse.mcpTools?.enabledServerIDs
        let selectedIDs = allowlist.map(Set.init) ?? eligibleIDs
        let resolvedIDs = selectedIDs.intersection(eligibleIDs)

        return eligibleServers
            .filter { resolvedIDs.contains($0.id) }
            .map { $0.toConfig() }
    }

    private func loadControlsFromConversation() {
        if let decoded = try? JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData) {
            controls = decoded
        } else {
            controls = GenerationControls()
        }

        normalizeControlsForCurrentSelection()
    }

    private func refreshExtensionCredentialsStatus() async {
        let defaults = UserDefaults.standard

        func hasStoredKey(_ key: String) -> Bool {
            let trimmed = (defaults.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
        }

        let mistralConfigured = hasStoredKey(AppPreferenceKeys.pluginMistralOCRAPIKey)
        let deepSeekConfigured = hasStoredKey(AppPreferenceKeys.pluginDeepSeekOCRAPIKey)

        let ttsProvider = try? SpeechPluginConfigFactory.currentTTSProvider(defaults: defaults)
        let sttProvider = try? SpeechPluginConfigFactory.currentSTTProvider(defaults: defaults)

        let ttsKeyConfigured = {
            guard let ttsProvider else { return false }
            let key: String
            switch ttsProvider {
            case .elevenlabs:
                key = AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:
                key = AppPreferenceKeys.ttsOpenAIAPIKey
            case .groq:
                key = AppPreferenceKeys.ttsGroqAPIKey
            }
            return hasStoredKey(key)
        }()

        let sttKeyConfigured = {
            guard let sttProvider else { return false }
            let key: String
            switch sttProvider {
            case .openai:
                key = AppPreferenceKeys.sttOpenAIAPIKey
            case .groq:
                key = AppPreferenceKeys.sttGroqAPIKey
            case .mistral:
                key = AppPreferenceKeys.sttMistralAPIKey
            }
            return hasStoredKey(key)
        }()

        let ttsConfigured: Bool
        if ttsProvider == .elevenlabs {
            let voiceID = (defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ttsConfigured = ttsKeyConfigured && !voiceID.isEmpty
        } else {
            ttsConfigured = ttsKeyConfigured
        }

        let mistralEnabled = AppPreferences.isPluginEnabled("mistral_ocr", defaults: defaults)
        let deepSeekEnabled = AppPreferences.isPluginEnabled("deepseek_ocr", defaults: defaults)
        let ttsEnabled = AppPreferences.isPluginEnabled("text_to_speech", defaults: defaults)
        let sttEnabled = AppPreferences.isPluginEnabled("speech_to_text", defaults: defaults)
        let webSearchSettings = WebSearchPluginSettingsStore.load(defaults: defaults)
        let webSearchEnabled = webSearchSettings.isEnabled
        let webSearchConfigured = SearchPluginProvider.allCases.contains {
            webSearchSettings.hasConfiguredCredential(for: $0)
        }

        await MainActor.run {
            mistralOCRConfigured = mistralConfigured
            deepSeekOCRConfigured = deepSeekConfigured
            textToSpeechConfigured = ttsConfigured
            speechToTextConfigured = sttKeyConfigured
            webSearchPluginConfigured = webSearchConfigured

            mistralOCRPluginEnabled = mistralEnabled
            deepSeekOCRPluginEnabled = deepSeekEnabled
            textToSpeechPluginEnabled = ttsEnabled
            speechToTextPluginEnabled = sttEnabled
            webSearchPluginEnabled = webSearchEnabled

            if !ttsEnabled {
                ttsPlaybackManager.stop()
            }
            if !sttEnabled {
                speechToTextManager.cancelAndCleanup()
            }
        }
    }

    private func currentSpeechToTextTranscriptionConfig() async throws -> SpeechToTextManager.TranscriptionConfig {
        try SpeechPluginConfigFactory.speechToTextConfig()
    }

    private func toggleSpeakAssistantMessage(_ messageEntity: MessageEntity, text: String) {
        Task { @MainActor in
            guard textToSpeechPluginEnabled else { return }

            let provider = try? SpeechPluginConfigFactory.currentTTSProvider()

            do {
                let config = try SpeechPluginConfigFactory.textToSpeechConfig()
                let context = TextToSpeechPlaybackManager.PlaybackContext(
                    conversationID: conversationEntity.id,
                    conversationTitle: conversationEntity.title,
                    textPreview: String(text.prefix(80))
                )
                ttsPlaybackManager.toggleSpeak(
                    messageID: messageEntity.id,
                    text: text,
                    config: config,
                    context: context,
                    onError: { error in
                        errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                        showingError = true
                    }
                )
            } catch {
                errorMessage = SpeechPluginConfigFactory.textToSpeechErrorMessage(error, provider: provider)
                showingError = true
            }
        }
    }

    private func stopSpeakAssistantMessage(_ messageEntity: MessageEntity) {
        ttsPlaybackManager.stop(messageID: messageEntity.id)
    }

    private func persistControlsToConversation() {
        do {
            conversationEntity.modelConfigData = try JSONEncoder().encode(controls)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func setReasoningOff() {
        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            updateReasoning { reasoning in
                reasoning.enabled = true
                if reasoning.effort == nil || reasoning.effort == ReasoningEffort.none {
                    reasoning.effort = selectedReasoningConfig?.defaultEffort ?? .medium
                }
            }
            persistControlsToConversation()
            return
        }

        updateReasoning { reasoning in
            reasoning.enabled = false
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
        persistControlsToConversation()
    }

    private func setReasoningOn() {
        updateReasoning { reasoning in
            reasoning.enabled = true
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
        persistControlsToConversation()
    }

    private func setReasoningEffort(_ effort: ReasoningEffort) {
        guard providerType != .anthropic else {
            openThinkingBudgetEditor()
            return
        }

        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.effort = effort
            reasoning.budgetTokens = nil
            if supportsReasoningSummaryControl, reasoning.summary == nil {
                reasoning.summary = .auto
            }
        }
        persistControlsToConversation()
    }

    private func setAnthropicThinkingBudget(_ budgetTokens: Int) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.effort = nil
            reasoning.budgetTokens = budgetTokens
            reasoning.summary = nil
        }
        normalizeAnthropicReasoningAndMaxTokens()
        persistControlsToConversation()
    }

    private var thinkingBudgetDraftInt: Int? {
        Int(thinkingBudgetDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var anthropicUsesEffortMode: Bool {
        guard providerType == .anthropic else { return false }
        return AnthropicModelLimits.supportsEffort(for: conversationEntity.modelID)
    }

    private var anthropicEffortBinding: Binding<ReasoningEffort> {
        Binding(
            get: {
                let value = controls.reasoning?.effort ?? selectedReasoningConfig?.defaultEffort ?? .high
                switch value {
                case .none, .minimal:
                    return .low
                case .low, .medium, .high, .xhigh:
                    return value
                }
            },
            set: { newValue in
                updateReasoning { reasoning in
                    reasoning.enabled = true
                    reasoning.effort = newValue
                    reasoning.budgetTokens = nil
                    reasoning.summary = nil
                }
                normalizeAnthropicReasoningAndMaxTokens()
                persistControlsToConversation()
            }
        )
    }

    private var anthropicThinkingSummaryText: String {
        if anthropicUsesEffortMode {
            return "Claude 4.6 uses adaptive thinking. Choose an effort level, then set a max output limit."
        }
        return "Claude 4.5 and earlier use budget-based thinking. Set budget tokens and max output tokens together."
    }

    private var anthropicThinkingFootnote: String {
        if anthropicUsesEffortMode {
            return "Sent as thinking.type=adaptive with output_config.effort."
        }
        return "Sent as thinking.type=enabled with budget_tokens."
    }

    private var anthropicDefaultBudgetTokens: Int {
        selectedReasoningConfig?.defaultBudget ?? 1024
    }

    private var anthropicBudgetPlaceholder: String {
        "\(anthropicDefaultBudgetTokens)"
    }

    private var anthropicMaxTokensPlaceholder: String {
        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID) {
            return "\(modelMax)"
        }
        return "4096"
    }

    private var maxTokensDraftInt: Int? {
        let trimmed = maxTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var isThinkingBudgetDraftValid: Bool {
        if !anthropicUsesEffortMode {
            guard let budget = thinkingBudgetDraftInt, budget > 0 else { return false }
        }
        guard providerType == .anthropic else { return true }
        guard let maxTokens = maxTokensDraftInt else { return false }
        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID), maxTokens > modelMax {
            return false
        }
        return true
    }

    private var thinkingBudgetValidationWarning: String? {
        guard providerType == .anthropic else { return nil }
        if !anthropicUsesEffortMode {
            guard let budget = thinkingBudgetDraftInt else { return "Enter an integer token budget (e.g., 4096)." }

            if budget <= 0 {
                return "Thinking budget must be a positive integer."
            }

            if let maxTokens = maxTokensDraftInt, maxTokens > 0, budget >= maxTokens {
                return "Recommended: keep budget tokens below max output tokens."
            }
        }

        if maxTokensDraftInt == nil {
            return "Enter a valid positive max output token value."
        }

        if let modelMax = AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID),
           let maxTokens = maxTokensDraftInt,
           maxTokens > modelMax {
            return "This model allows at most \(modelMax) max output tokens."
        }

        return nil
    }

    private func openThinkingBudgetEditor() {
        if anthropicUsesEffortMode {
            thinkingBudgetDraft = ""
        } else {
            let budget = controls.reasoning?.budgetTokens
                ?? selectedReasoningConfig?.defaultBudget
                ?? anthropicDefaultBudgetTokens
            thinkingBudgetDraft = "\(budget)"
        }

        if providerType == .anthropic {
            let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
                requested: controls.maxTokens,
                for: conversationEntity.modelID,
                fallback: 4096
            )
            maxTokensDraft = "\(resolvedMax)"
        } else {
            maxTokensDraft = controls.maxTokens.map(String.init) ?? ""
        }

        showingThinkingBudgetSheet = true
    }

    private func applyThinkingBudgetDraft() {
        guard providerType != .anthropic || maxTokensDraftInt != nil else { return }

        controls.maxTokens = maxTokensDraftInt

        if anthropicUsesEffortMode {
            normalizeAnthropicReasoningAndMaxTokens()
        } else {
            guard let budgetTokens = thinkingBudgetDraftInt else { return }
            setAnthropicThinkingBudget(budgetTokens)
        }

        if providerType == .anthropic {
            let resolvedMax = AnthropicModelLimits.resolvedMaxTokens(
                requested: controls.maxTokens,
                for: conversationEntity.modelID,
                fallback: 4096
            )
            maxTokensDraft = "\(resolvedMax)"
        }

        persistControlsToConversation()
    }

    private func normalizeAnthropicReasoningAndMaxTokens() {
        guard providerType == .anthropic else { return }

        if controls.reasoning?.enabled == true {
            if anthropicUsesEffortMode {
                controls.reasoning?.budgetTokens = nil
                if controls.reasoning?.effort == nil || controls.reasoning?.effort == ReasoningEffort.none {
                    controls.reasoning?.effort = selectedReasoningConfig?.defaultEffort ?? .high
                }
            } else {
                controls.reasoning?.effort = nil
                if controls.reasoning?.budgetTokens == nil {
                    controls.reasoning?.budgetTokens = anthropicDefaultBudgetTokens
                }
            }

            controls.maxTokens = AnthropicModelLimits.resolvedMaxTokens(
                requested: controls.maxTokens,
                for: conversationEntity.modelID,
                fallback: 4096
            )
        } else {
            controls.reasoning?.effort = nil
            controls.reasoning?.budgetTokens = nil
            controls.maxTokens = nil
        }
    }

    private func setReasoningSummary(_ summary: ReasoningSummary) {
        updateReasoning { reasoning in
            reasoning.enabled = true
            reasoning.summary = summary
            if supportsReasoningSummaryControl,
               (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
                reasoning.effort = selectedReasoningConfig?.defaultEffort ?? .medium
            }
        }
        persistControlsToConversation()
    }

    private func updateReasoning(_ mutate: (inout ReasoningControls) -> Void) {
        var reasoning = controls.reasoning ?? ReasoningControls(enabled: false)
        mutate(&reasoning)
        controls.reasoning = reasoning
    }

    private func defaultWebSearchControls(enabled: Bool) -> WebSearchControls {
        guard enabled else { return WebSearchControls(enabled: false) }

        switch providerType {
        case .openai, .openaiWebSocket:
            return WebSearchControls(enabled: true, contextSize: .medium, sources: nil)
        case .perplexity:
            // Perplexity defaults `search_context_size` to `low` when omitted.
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        case .xai:
            return WebSearchControls(enabled: true, contextSize: nil, sources: [.web])
        case .anthropic:
            return WebSearchControls(enabled: true)
        case .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        }
    }

    private func ensureValidWebSearchDefaultsIfEnabled() {
        guard controls.webSearch?.enabled == true else { return }
        switch providerType {
        case .openai, .openaiWebSocket:
            controls.webSearch?.sources = nil
            if controls.webSearch?.contextSize == nil {
                controls.webSearch?.contextSize = .medium
            }
        case .perplexity:
            controls.webSearch?.sources = nil
            // Leave contextSize nil to use Perplexity defaults unless explicitly set.
        case .xai:
            controls.webSearch?.contextSize = nil
            let sources = controls.webSearch?.sources ?? []
            if sources.isEmpty {
                controls.webSearch?.sources = [.web]
            }
        case .anthropic:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
            normalizeAnthropicDomainFilters()
        case .codexAppServer, .openaiCompatible, .openrouter, .groq, .cohere, .mistral, .deepinfra, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
        }
    }

    private func normalizeControlsForCurrentSelection() {
        let originalData = (try? JSONEncoder().encode(controls)) ?? Data()

        normalizeMaxTokensForModel()
        normalizeMediaGenerationOverrides()
        normalizeReasoningControls()
        normalizeReasoningEffortLimits()
        normalizeVertexAIGenerationConfig()
        normalizeFireworksProviderSpecific()
        normalizeWebSearchControls()
        normalizeSearchPluginControls()
        normalizeContextCacheControls()
        normalizeMCPToolsControls()
        normalizeAnthropicMaxTokens()
        normalizeImageGenerationControls()
        normalizeVideoGenerationControls()

        let newData = (try? JSONEncoder().encode(controls)) ?? Data()
        if newData != originalData {
            persistControlsToConversation()
        }
    }

    private func normalizeMaxTokensForModel() {
        if let modelMaxOutput = resolvedModelSettings?.maxOutputTokens,
           let requested = controls.maxTokens,
           requested > modelMaxOutput {
            controls.maxTokens = modelMaxOutput
        }
    }

    private func normalizeMediaGenerationOverrides() {
        guard supportsMediaGenerationControl else { return }
        if !supportsReasoningControl {
            controls.reasoning = nil
        }
        if !supportsWebSearchControl {
            controls.webSearch = nil
        }
        controls.searchPlugin = nil
        controls.mcpTools = nil
    }

    private func normalizeReasoningControls() {
        if supportsReasoningControl, let reasoningConfig = selectedReasoningConfig {
            switch reasoningConfig.type {
            case .effort:
                normalizeEffortBasedReasoning(config: reasoningConfig)
            case .budget:
                normalizeBudgetBasedReasoning(config: reasoningConfig)
            case .toggle:
                normalizeToggleBasedReasoning()
            case .none:
                controls.reasoning = nil
            }
        } else if !supportsReasoningControl {
            controls.reasoning = nil
        }
    }

    private func normalizeEffortBasedReasoning(config: ModelReasoningConfig) {
        if providerType != .anthropic,
           controls.reasoning?.enabled == true,
           controls.reasoning?.effort == nil {
            updateReasoning { $0.effort = config.defaultEffort ?? .medium }
        }

        if providerType == .fireworks, isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            if controls.reasoning == nil {
                controls.reasoning = ReasoningControls(
                    enabled: true,
                    effort: config.defaultEffort ?? .medium,
                    budgetTokens: nil,
                    summary: nil
                )
            }
            controls.reasoning?.enabled = true
            if controls.reasoning?.effort == nil || controls.reasoning?.effort == ReasoningEffort.none {
                controls.reasoning?.effort = config.defaultEffort ?? .medium
            }
        }

        if providerType != .anthropic {
            controls.reasoning?.budgetTokens = nil
        }
        if supportsReasoningSummaryControl,
           controls.reasoning?.enabled == true,
           (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
           controls.reasoning?.summary == nil {
            controls.reasoning?.summary = .auto
        }
        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
    }

    private func normalizeBudgetBasedReasoning(config: ModelReasoningConfig) {
        if controls.reasoning?.enabled == true, controls.reasoning?.budgetTokens == nil {
            updateReasoning { $0.budgetTokens = config.defaultBudget ?? 2048 }
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.summary = nil
    }

    private func normalizeToggleBasedReasoning() {
        if controls.reasoning == nil {
            controls.reasoning = ReasoningControls(enabled: true)
        }
        controls.reasoning?.effort = nil
        controls.reasoning?.budgetTokens = nil
        controls.reasoning?.summary = nil
    }

    private func normalizeReasoningEffortLimits() {
        guard supportsReasoningControl else { return }

        if let effort = controls.reasoning?.effort {
            controls.reasoning?.effort = ModelCapabilityRegistry.normalizedReasoningEffort(
                effort,
                for: providerType,
                modelID: conversationEntity.modelID
            )
        }

        if providerType == .anthropic {
            normalizeAnthropicReasoningAndMaxTokens()
        }
    }

    private func normalizeVertexAIGenerationConfig() {
        guard providerType == .vertexai,
              var generationConfig = controls.providerSpecific["generationConfig"]?.value as? [String: Any] else {
            return
        }

        var mutated = false

        if lowerModelID == "gemini-3-pro-image-preview" {
            if generationConfig["thinkingConfig"] != nil {
                generationConfig.removeValue(forKey: "thinkingConfig")
                mutated = true
            }
        } else if Self.vertexGemini25TextModelIDs.contains(lowerModelID),
                  var thinkingConfig = generationConfig["thinkingConfig"] as? [String: Any],
                  thinkingConfig["thinkingLevel"] != nil {
            thinkingConfig.removeValue(forKey: "thinkingLevel")
            if thinkingConfig.isEmpty {
                generationConfig.removeValue(forKey: "thinkingConfig")
            } else {
                generationConfig["thinkingConfig"] = thinkingConfig
            }
            mutated = true
        }

        guard mutated else { return }
        if generationConfig.isEmpty {
            controls.providerSpecific.removeValue(forKey: "generationConfig")
        } else {
            controls.providerSpecific["generationConfig"] = AnyCodable(generationConfig)
        }
    }

    private func normalizeFireworksProviderSpecific() {
        guard providerType == .fireworks else { return }

        if isFireworksMiniMaxM2FamilyModel(conversationEntity.modelID) {
            controls.providerSpecific.removeValue(forKey: "reasoning_effort")
        }

        if let rawHistory = controls.providerSpecific["reasoning_history"]?.value as? String {
            let normalized = rawHistory.lowercased()
            if fireworksReasoningHistoryOptions.contains(normalized) {
                controls.providerSpecific["reasoning_history"] = AnyCodable(normalized)
            } else {
                controls.providerSpecific.removeValue(forKey: "reasoning_history")
            }
        } else if controls.providerSpecific["reasoning_history"] != nil {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
    }

    private func normalizeWebSearchControls() {
        if supportsWebSearchControl {
            if controls.webSearch?.enabled == true {
                ensureValidWebSearchDefaultsIfEnabled()
            }
        } else {
            controls.webSearch = nil
        }
    }

    private func normalizeSearchPluginControls() {
        if !supportsBuiltinSearchPluginControl {
            controls.searchPlugin = nil
            return
        }

        guard controls.webSearch?.enabled == true else {
            controls.searchPlugin = nil
            return
        }

        guard var plugin = controls.searchPlugin else {
            return
        }

        if let maxResults = plugin.maxResults {
            plugin.maxResults = max(1, min(50, maxResults))
        }
        if let recencyDays = plugin.recencyDays {
            plugin.recencyDays = max(1, min(365, recencyDays))
        }

        controls.searchPlugin = plugin
    }

    private func normalizeContextCacheControls() {
        if supportsContextCacheControl {
            if var contextCache = controls.contextCache {
                if !supportsExplicitContextCacheMode, contextCache.mode == .explicit {
                    contextCache.mode = .implicit
                    contextCache.cachedContentName = nil
                }
                if !supportsContextCacheStrategy {
                    contextCache.strategy = nil
                } else if contextCache.strategy == nil {
                    contextCache.strategy = .systemOnly
                }
                if !supportsContextCacheTTL {
                    contextCache.ttl = nil
                }
                if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
                    contextCache.cacheKey = nil
                }
                if providerType != .xai {
                    contextCache.minTokensThreshold = nil
                }
                if providerType != .xai {
                    contextCache.conversationID = nil
                }
                if providerType != .gemini && providerType != .vertexai {
                    contextCache.cachedContentName = nil
                }
                if contextCache.mode == .off, providerType != .anthropic {
                    controls.contextCache = nil
                } else {
                    controls.contextCache = contextCache
                }
            }
        } else {
            controls.contextCache = nil
        }
    }

    private func normalizeMCPToolsControls() {
        if supportsMCPToolsControl {
            if controls.mcpTools == nil {
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
            } else if controls.mcpTools?.enabledServerIDs?.isEmpty == true {
                controls.mcpTools?.enabledServerIDs = nil
            }
        } else {
            controls.mcpTools = nil
        }
    }

    private func normalizeAnthropicMaxTokens() {
        if !supportsReasoningControl, providerType == .anthropic {
            controls.maxTokens = nil
        }
        if providerType == .anthropic,
           controls.maxTokens != nil,
           controls.reasoning?.enabled != true {
            controls.maxTokens = nil
        }
    }

    private func normalizeImageGenerationControls() {
        if supportsImageGenerationControl {
            if providerType == .xai {
                controls.imageGeneration = nil
                if var xaiImage = controls.xaiImageGeneration {
                    xaiImage.quality = nil
                    xaiImage.style = nil
                    if xaiImage.aspectRatio != nil {
                        xaiImage.size = nil
                    }
                    controls.xaiImageGeneration = xaiImage.isEmpty ? nil : xaiImage
                }
            } else {
                if !supportsCurrentModelImageSizeControl {
                    controls.imageGeneration?.imageSize = nil
                }
                if providerType != .vertexai {
                    controls.imageGeneration?.vertexPersonGeneration = nil
                    controls.imageGeneration?.vertexOutputMIMEType = nil
                    controls.imageGeneration?.vertexCompressionQuality = nil
                }
                if controls.imageGeneration?.isEmpty == true {
                    controls.imageGeneration = nil
                }
                controls.xaiImageGeneration = nil
            }
        } else {
            controls.imageGeneration = nil
            controls.xaiImageGeneration = nil
        }
    }

    private func normalizeVideoGenerationControls() {
        if supportsVideoGenerationControl {
            if controls.xaiVideoGeneration?.isEmpty == true {
                controls.xaiVideoGeneration = nil
            }
        } else {
            controls.xaiVideoGeneration = nil
        }
    }

    private var builtinSearchIncludeRawBinding: Binding<Bool> {
        Binding(
            get: {
                controls.searchPlugin?.includeRawContent ?? false
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.includeRawContent = newValue ? true : nil
                persistControlsToConversation()
            }
        )
    }

    private var builtinSearchFetchPageBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.fetchPageContent ?? settings.jinaReadPages
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.fetchPageContent = newValue
                persistControlsToConversation()
            }
        )
    }

    private var builtinSearchExaAutopromptBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.exaUseAutoprompt ?? settings.exaUseAutoprompt
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.exaUseAutoprompt = newValue
                persistControlsToConversation()
            }
        )
    }

    private var builtinSearchFirecrawlExtractBinding: Binding<Bool> {
        Binding(
            get: {
                let settings = WebSearchPluginSettingsStore.load()
                return controls.searchPlugin?.firecrawlExtractContent ?? settings.firecrawlExtractContent
            },
            set: { newValue in
                if controls.searchPlugin == nil {
                    controls.searchPlugin = SearchPluginControls()
                }
                controls.searchPlugin?.firecrawlExtractContent = newValue
                persistControlsToConversation()
            }
        )
    }


    private func webSearchSourceBinding(_ source: WebSearchSource) -> Binding<Bool> {
        Binding(
            get: {
                Set(controls.webSearch?.sources ?? []).contains(source)
            },
            set: { isOn in
                var set = Set(controls.webSearch?.sources ?? [])
                if isOn {
                    set.insert(source)
                } else {
                    set.remove(source)
                }
                controls.webSearch?.sources = Array(set).sorted { $0.rawValue < $1.rawValue }
                persistControlsToConversation()
            }
        )
    }
}

private struct BuiltinToolActivityPayload: Decodable {
    let provider: SearchPluginProvider
    let query: String
    let results: [BuiltinToolActivityPayloadRow]
}

private struct BuiltinToolActivityPayloadRow: Decodable {
    let title: String
    let url: String
    let snippet: String?
    let publishedAt: String?
    let source: String?
}
