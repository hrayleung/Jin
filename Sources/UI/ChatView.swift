import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import Combine
import AVFoundation
import AVKit

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var streamingStore: ConversationStreamingStore
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    var onPersistConversationIfNeeded: () -> Void = {}
    @Query private var providers: [ProviderConfigEntity]
    @Query private var mcpServers: [MCPServerConfigEntity]

    @State private var controls: GenerationControls = GenerationControls()
    @State private var messageText = ""
    @State private var draftAttachments: [DraftAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var isComposerDropTargeted = false
    @State private var isComposerFocused = false
    @State private var editingUserMessageID: UUID?
    @State private var editingUserMessageText = ""
    @State private var isEditingUserMessageFocused = false
    @State private var composerHeight: CGFloat = 0
    @State private var isModelPickerPresented = false
    @State private var messageRenderLimit: Int = 160
    @State private var pendingRestoreScrollMessageID: UUID?
    @State private var isPinnedToBottom = true
    @State private var lastStreamingAutoScrollUptime: TimeInterval = 0

    // Cache expensive derived data so typing/streaming doesn't repeatedly sort/decode the entire history.
    @State private var cachedVisibleMessages: [MessageRenderItem] = []
    @State private var cachedMessagesVersion: Int = 0
    @State private var cachedMessageEntitiesByID: [UUID: MessageEntity] = [:]
    @State private var cachedNormalizedMarkdownByKey: [MarkdownNormalizationCacheKey: String] = [:]
    @State private var cachedToolResultsByCallID: [String: ToolResult] = [:]
    @State private var lastCacheRebuildMessageCount: Int = 0
    @State private var lastCacheRebuildUpdatedAt: Date = .distantPast

    @ObservedObject private var favoriteModelsStore = FavoriteModelsStore.shared

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingThinkingBudgetSheet = false
    @State private var thinkingBudgetDraft = ""
    @State private var maxTokensDraft = ""

    @State private var showingProviderSpecificParamsSheet = false
    @State private var providerSpecificParamsDraft = ""
    @State private var providerSpecificParamsError: String?
    @State private var providerSpecificParamsBaselineControls: GenerationControls?
    @State private var providerSpecificParamsEditorID = UUID()

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
    @State private var isPreparingToSend = false
    @State private var prepareToSendStatus: String?
    @State private var prepareToSendTask: Task<Void, Never>?
    @StateObject private var ttsPlaybackManager = TextToSpeechPlaybackManager()
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
    }

    @ViewBuilder
    private var composerLeftColumn: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            composerAttachmentChipsRow
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
                onDropFileURLs: handleDroppedFileURLs,
                onDropImages: handleDroppedImages,
                onSubmit: handleComposerSubmit,
                onCancel: handleComposerCancel
            )
            .frame(height: 36)
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
                .disabled(isBusy || speechToTextManager.isTranscribing || (!speechToTextConfigured && !speechToTextManager.isRecording))
            }

            Button { isFileImporterPresented = true } label: {
                controlIconLabel(
                    systemName: "paperclip",
                    isActive: !draftAttachments.isEmpty,
                    badgeText: draftAttachments.isEmpty ? nil : "\(draftAttachments.count)"
                )
            }
            .buttonStyle(.plain)
            .help(supportsNativePDF ? "Attach images / PDFs (Native PDF support ✓)" : "Attach images / PDFs")
            .disabled(isBusy)

            if supportsPDFProcessingControl {
                if supportsNativePDF {
                    Image(systemName: "doc.richtext.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Model supports native PDF reading")
                }

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

            Menu { providerSpecificParamsMenuContent } label: {
                controlIconLabel(
                    systemName: "slider.horizontal.3",
                    isActive: !controls.providerSpecific.isEmpty,
                    badgeText: providerSpecificParamsBadgeText
                )
            }
            .menuStyle(.borderlessButton)
            .help(providerSpecificParamsHelpText)

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
                Text("Transcribing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Message list
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        let bubbleMaxWidth = maxBubbleWidth(for: geometry.size.width)
                        let assistantDisplayName = conversationEntity.assistant?.displayName ?? "Assistant"
                        let providerIconID = currentProviderIconID
                        let toolResultsByCallID = cachedToolResultsByCallID
                        let messageEntitiesByID = cachedMessageEntitiesByID

                        let allMessages = cachedVisibleMessages
                        let visibleMessages = allMessages.suffix(messageRenderLimit)
                        let hiddenCount = allMessages.count - visibleMessages.count

                        LazyVStack(alignment: .leading, spacing: 16) { // Improved spacing between messages
                            if hiddenCount > 0 {
                                LoadEarlierMessagesRow(
                                    hiddenCount: hiddenCount,
                                    pageSize: 120,
                                    onLoad: {
                                        guard let firstVisible = visibleMessages.first else { return }
                                        pendingRestoreScrollMessageID = firstVisible.id
                                        messageRenderLimit = min(allMessages.count, messageRenderLimit + 120)
                                    }
                                )
                                .id("loadEarlier")
                            }

                            ForEach(visibleMessages) { message in
                                MessageRow(
                                    item: message,
                                    maxBubbleWidth: bubbleMaxWidth,
                                    assistantDisplayName: assistantDisplayName,
                                    providerIconID: providerIconID,
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
                                    onContentUpdate: {
                                        throttledScrollToBottom(proxy: proxy)
                                    }
                                )
                                .id("streaming")
                            }

                            Color.clear
                                .frame(height: composerHeight + 24)
                                .id("bottom")
                                .background {
                                    GeometryReader { bottomGeo in
                                        Color.clear.preference(
                                            key: BottomSentinelMaxYPreferenceKey.self,
                                            value: bottomGeo.frame(in: .named("chatScroll")).maxY
                                        )
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    }
                    .coordinateSpace(name: "chatScroll")
                    .onPreferenceChange(BottomSentinelMaxYPreferenceKey.self) { sentinelMaxY in
                        let threshold: CGFloat = 80
                        let pinned = sentinelMaxY <= geometry.size.height + threshold
                        if pinned != isPinnedToBottom {
                            isPinnedToBottom = pinned
                        }
                    }
                    .onAppear {
                        // On first open, jump to the latest message instead of the start of the conversation.
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: conversationEntity.id) { _, _ in
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: cachedMessagesVersion) { _, _ in
                        guard isPinnedToBottom else { return }
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: streamingMessage != nil) { _, isActive in
                        if isActive {
                            lastStreamingAutoScrollUptime = 0
                        }
                        guard isPinnedToBottom else { return }
                        // Ensure the streaming row has been laid out before scrolling to it.
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: composerHeight) { _, _ in
                        guard isPinnedToBottom else { return }
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: messageRenderLimit) { _, _ in
                        guard let restoreID = pendingRestoreScrollMessageID else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo(restoreID, anchor: .top)
                            pendingRestoreScrollMessageID = nil
                        }
                    }
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
        .toolbarBackground(JinSemanticColor.detailSurface, for: .windowToolbar)
        .navigationTitle(conversationEntity.title)
        .navigationSubtitle(currentModelName)
        .toolbar {
            ToolbarItemGroup {
                modelPickerButton

                let isStarred = conversationEntity.isStarred == true
                Button {
                    conversationEntity.isStarred = !isStarred
                } label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? Color.orange : Color.primary)
                }
                .help(isStarred ? "Unstar chat" : "Star chat")

                Button {
                    isAssistantInspectorPresented = true
                } label: {
                    Label("Assistant Settings", systemImage: "slider.horizontal.3")
                }
                .help("Assistant Settings")
                .keyboardShortcut("i", modifiers: [.command])

                Button(role: .destructive) {
                    onRequestDeleteConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete chat")
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
        .onAppear {
            isComposerFocused = true
            rebuildMessageCaches()
        }
        .onChange(of: conversationEntity.id) { _, _ in
            // Switching chats: reset transient per-chat state and rebuild caches.
            cancelEditingUserMessage()
            messageRenderLimit = 160
            pendingRestoreScrollMessageID = nil
            isPinnedToBottom = true
            lastStreamingAutoScrollUptime = 0
            ttsPlaybackManager.stop()
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
            allowedContentTypes: [.image, .pdf],
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
            NavigationStack {
                Form {
                    Section("Claude thinking") {
                        VStack(alignment: .leading, spacing: JinSpacing.medium) {
                            Text(anthropicThinkingSummaryText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            if anthropicUsesEffortMode {
                                thinkingControlRow("Thinking effort") {
                                    Picker("Thinking effort", selection: anthropicEffortBinding) {
                                        Text("Low").tag(ReasoningEffort.low)
                                        Text("Medium").tag(ReasoningEffort.medium)
                                        Text("High").tag(ReasoningEffort.high)
                                        if AnthropicModelLimits.supportsMaxEffort(for: conversationEntity.modelID) {
                                            Text("Max").tag(ReasoningEffort.xhigh)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 180, alignment: .trailing)
                                }
                            } else {
                                thinkingControlRow("Thinking budget") {
                                    thinkingTokenField(placeholder: anthropicBudgetPlaceholder, text: $thinkingBudgetDraft)
                                }
                            }

                            thinkingControlRow("Max output tokens") {
                                thinkingTokenField(placeholder: anthropicMaxTokensPlaceholder, text: $maxTokensDraft)
                            }

                            if let modelMax = AnthropicModelLimits.maxOutputTokens(for: conversationEntity.modelID) {
                                Text("Model max output tokens: \(modelMax.formatted())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let warning = thinkingBudgetValidationWarning {
                                HStack(alignment: .top, spacing: JinSpacing.small) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(warning)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.caption)
                                .padding(JinSpacing.small)
                                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                            }

                            Label(anthropicThinkingFootnote, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(JinSpacing.large)
                        .jinSurface(.raised, cornerRadius: JinRadius.large)
                        .listRowInsets(
                            EdgeInsets(
                                top: JinSpacing.small,
                                leading: JinSpacing.small,
                                bottom: JinSpacing.small,
                                trailing: JinSpacing.small
                            )
                        )
                        .listRowBackground(Color.clear)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background {
                    JinSemanticColor.detailSurface
                        .ignoresSafeArea()
                }
                .navigationTitle("Thinking")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingThinkingBudgetSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            applyThinkingBudgetDraft()
                            showingThinkingBudgetSheet = false
                        }
                        .disabled(!isThinkingBudgetDraftValid)
                    }
                }
            }
            .frame(minWidth: 640, idealWidth: 700)
        }
        .sheet(isPresented: $showingProviderSpecificParamsSheet) {
            NavigationStack {
                Form {
                    Section("Request parameters (JSON)") {
                        TextEditor(text: $providerSpecificParamsDraft)
                            .id(providerSpecificParamsEditorID)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 220)
                            .padding(JinSpacing.small)
                            .lineSpacing(3)
                            .jinSurface(.raised, cornerRadius: JinRadius.small)
                            .onChange(of: providerSpecificParamsDraft) { _, _ in
                                providerSpecificParamsError = nil
                            }

                        if let providerSpecificParamsError {
                            Text(providerSpecificParamsError)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(JinSpacing.small)
                                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                        } else {
                            Text("Edits sync with the UI when a matching control exists. Unrecognized fields are stored as provider-specific overrides.")
                                .jinInfoCallout()
                        }
                    }

                    Section("Examples") {
                        VStack(alignment: .leading, spacing: JinSpacing.small) {
                            Text("Perplexity disable search: {\"disable_search\": true}")
                            Text("Perplexity academic search: {\"search_mode\": \"academic\"}")
                            Text("Fireworks GLM/Kimi thinking history: {\"reasoning_history\": \"preserved\"} (or \"interleaved\" / \"turn_level\")")
                            Text("Cerebras GLM preserved thinking: {\"clear_thinking\": false}")
                            Text("Cerebras GLM disable thinking: {\"disable_reasoning\": true}")
                            Text("Cerebras reasoning output: {\"reasoning_format\": \"parsed\"} (or \"raw\" / \"hidden\" / \"none\")")
                            Text("Gemini image generation: {\"generationConfig\": {\"responseModalities\": [\"TEXT\", \"IMAGE\"], \"imageConfig\": {\"aspectRatio\": \"16:9\", \"imageSize\": \"2K\"}}}")
                            Text("Vertex image extras: {\"generationConfig\": {\"imageConfig\": {\"personGeneration\": \"ALLOW_ADULT\", \"imageOutputOptions\": {\"mimeType\": \"image/jpeg\", \"compressionQuality\": 90}}}}")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(JinSpacing.small)
                        .jinSurface(.raised, cornerRadius: JinRadius.small)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(JinSemanticColor.detailSurface)
                .navigationTitle("Provider Params")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            providerSpecificParamsBaselineControls = nil
                            showingProviderSpecificParamsSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if applyProviderSpecificParamsDraft() {
                                showingProviderSpecificParamsSheet = false
                            }
                        }
                        .disabled(!isProviderSpecificParamsDraftValid)
                    }
                }
            }
            .frame(width: 560, height: 520)
        }
        .sheet(isPresented: $showingImageGenerationSheet) {
            NavigationStack {
                Form {
                    Section("Output") {
                        Picker(
                            "Response",
                            selection: Binding(
                                get: { imageGenerationDraft.responseMode ?? .textAndImage },
                                set: { value in
                                    imageGenerationDraft.responseMode = (value == .textAndImage) ? nil : value
                                }
                            )
                        ) {
                            ForEach(ImageResponseMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        Picker("Aspect Ratio", selection: $imageGenerationDraft.aspectRatio) {
                            Text("Default").tag(Optional<ImageAspectRatio>.none)
                            ForEach(ImageAspectRatio.allCases, id: \.self) { ratio in
                                Text(ratio.displayName).tag(Optional(ratio))
                            }
                        }

                        if supportsCurrentModelImageSizeControl {
                            Picker("Image Size", selection: $imageGenerationDraft.imageSize) {
                                Text("Default").tag(Optional<ImageOutputSize>.none)
                                ForEach(ImageOutputSize.allCases, id: \.self) { size in
                                    Text(size.displayName).tag(Optional(size))
                                }
                            }
                        }

                        TextField("Seed (optional)", text: $imageGenerationSeedDraft)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                    }

                    if providerType == .vertexai {
                        Section("Vertex") {
                            Picker("Person generation", selection: $imageGenerationDraft.vertexPersonGeneration) {
                                Text("Default").tag(Optional<VertexImagePersonGeneration>.none)
                                ForEach(VertexImagePersonGeneration.allCases, id: \.self) { item in
                                    Text(item.displayName).tag(Optional(item))
                                }
                            }

                            Picker("Output MIME", selection: $imageGenerationDraft.vertexOutputMIMEType) {
                                Text("Default").tag(Optional<VertexImageOutputMIMEType>.none)
                                ForEach(VertexImageOutputMIMEType.allCases, id: \.self) { item in
                                    Text(item.displayName).tag(Optional(item))
                                }
                            }

                            TextField("JPEG quality 0-100 (optional)", text: $imageGenerationCompressionQualityDraft)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let imageGenerationDraftError {
                        Section {
                            Text(imageGenerationDraftError)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
                .navigationTitle("Image Generation")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingImageGenerationSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if applyImageGenerationDraft() {
                                showingImageGenerationSheet = false
                            }
                        }
                        .disabled(!isImageGenerationDraftValid)
                    }
                }
            }
            .frame(width: 500)
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
                attach: { isFileImporterPresented = true },
                stopStreaming: {
                    guard isBusy else { return }
                    sendMessage()
                }
            )
        )
    }
    
    // MARK: - Helpers & Subviews

    private enum AttachmentConstants {
        static let maxDraftAttachments = 8
        static let maxAttachmentBytes = 25 * 1024 * 1024
        static let maxPDFExtractedCharacters = 120_000
        static let maxMistralOCRImagesToAttach = 8
        static let maxMistralOCRTotalImageBytes = 12 * 1024 * 1024
    }

    private struct AttachmentImportError: LocalizedError, Sendable {
        let message: String

        var errorDescription: String? { message }
    }

    private struct DraftAttachment: Identifiable, Hashable, Sendable {
        let id: UUID
        let filename: String
        let mimeType: String
        let fileURL: URL
        let extractedText: String?

        var isImage: Bool { mimeType.hasPrefix("image/") }
        var isPDF: Bool { mimeType == "application/pdf" }
    }

    private var trimmedMessageText: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var speechToTextHelpText: String {
        if speechToTextManager.isTranscribing { return "Transcribing…" }
        if speechToTextManager.isRecording { return "Stop recording" }
        if !speechToTextPluginEnabled { return "Speech to Text is turned off in Settings → Plugins" }
        if !speechToTextConfigured { return "Configure Speech to Text in Settings → Plugins → Speech to Text" }
        return "Start recording"
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
        let uniqueURLs = Array(Set(urls))
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
            guard let url = Self.writeTemporaryPNG(from: image) else {
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

                    if let url = Self.urlFromItemProviderItem(item) {
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

                    guard let tempURL = Self.writeTemporaryPNG(from: image) else {
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
                        let parsed = Self.parseDroppedString(text)
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

    private static func urlFromItemProviderItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        if let string = item as? NSString { return URL(string: string as String) }
        return nil
    }

    private static func writeTemporaryPNG(from image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        if data.count > AttachmentConstants.maxAttachmentBytes {
            return nil
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JinDroppedImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    static func parseDroppedString(_ text: String) -> (fileURLs: [URL], textChunks: [String]) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var fileURLs: [URL] = []
        var textChunks: [String] = []

        for line in lines {
            if line.hasPrefix("file://"), let url = URL(string: line), url.isFileURL {
                fileURLs.append(url)
                continue
            }

            let expanded = (line as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                let url = URL(fileURLWithPath: expanded)
                if isPotentialAttachmentFile(url) {
                    fileURLs.append(url)
                    continue
                }
            }

            textChunks.append(line)
        }

        return (fileURLs: fileURLs, textChunks: textChunks)
    }

    private static func isPotentialAttachmentFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        return ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp"
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
            await Self.importAttachmentsInBackground(from: urlsToImport)
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

    private static func importAttachmentsInBackground(from urls: [URL]) async -> ([DraftAttachment], [String]) {
        var newAttachments: [DraftAttachment] = []
        var errors: [String] = []

        let storage: AttachmentStorageManager
        do {
            storage = try AttachmentStorageManager()
        } catch {
            return ([], ["Failed to initialize attachment storage: \(error.localizedDescription)"])
        }

        for sourceURL in urls {
            let result = await importSingleAttachment(from: sourceURL, storage: storage)
            switch result {
            case .success(let attachment):
                newAttachments.append(attachment)
            case .failure(let error):
                errors.append(error.localizedDescription)
            }
        }

        return (newAttachments, errors)
    }

    private static func importSingleAttachment(from sourceURL: URL, storage: AttachmentStorageManager) async -> Result<DraftAttachment, AttachmentImportError> {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.isFileURL else {
            return .failure(AttachmentImportError(message: "Unsupported item: \(sourceURL.lastPathComponent)"))
        }

        let filename = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        let resourceValues = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if resourceValues?.isDirectory == true {
            return .failure(AttachmentImportError(message: "\(filename): folders are not supported."))
        }

        let fileSize = resourceValues?.fileSize ?? 0
        if fileSize > AttachmentConstants.maxAttachmentBytes {
            return .failure(AttachmentImportError(message: "\(filename): exceeds \(AttachmentConstants.maxAttachmentBytes / (1024 * 1024))MB limit."))
        }

        guard let type = UTType(filenameExtension: sourceURL.pathExtension.lowercased()) else {
            if let convertedURL = convertImageFileToTemporaryPNG(at: sourceURL) {
                let base = (filename as NSString).deletingPathExtension
                let outputName = base.isEmpty ? "Image.png" : "\(base).png"
                return await saveConvertedPNG(
                    convertedURL,
                    storage: storage,
                    filename: outputName
                )
            }
            return .failure(AttachmentImportError(message: "\(filename): unsupported file type."))
        }

        if type.conforms(to: .pdf) {
            let mimeType = "application/pdf"
            do {
                let entity = try await storage.saveAttachment(from: sourceURL, filename: filename, mimeType: mimeType)
                return .success(
                    DraftAttachment(
                        id: entity.id,
                        filename: entity.filename,
                        mimeType: entity.mimeType,
                        fileURL: entity.fileURL,
                        extractedText: nil
                    )
                )
            } catch {
                return .failure(AttachmentImportError(message: "\(filename): failed to import (\(error.localizedDescription))."))
            }
        }

        if type.conforms(to: .image) {
            let supported: Set<String> = ["image/png", "image/jpeg", "image/webp"]

            if let rawMimeType = type.preferredMIMEType {
                let mimeType = (rawMimeType == "image/jpg") ? "image/jpeg" : rawMimeType
                if supported.contains(mimeType) {
                    do {
                        let entity = try await storage.saveAttachment(from: sourceURL, filename: filename, mimeType: mimeType)
                        return .success(
                            DraftAttachment(
                                id: entity.id,
                                filename: entity.filename,
                                mimeType: entity.mimeType,
                                fileURL: entity.fileURL,
                                extractedText: nil
                            )
                        )
                    } catch {
                        return .failure(AttachmentImportError(message: "\(filename): failed to import (\(error.localizedDescription))."))
                    }
                }
            }

            guard let convertedURL = convertImageFileToTemporaryPNG(at: sourceURL) else {
                let rawMimeType = type.preferredMIMEType ?? "unknown"
                return .failure(AttachmentImportError(message: "\(filename): unsupported image format (\(rawMimeType)). Use PNG/JPEG/WebP."))
            }

            let base = (filename as NSString).deletingPathExtension
            let outputName = base.isEmpty ? "Image.png" : "\(base).png"
            return await saveConvertedPNG(
                convertedURL,
                storage: storage,
                filename: outputName
            )
        }

        return .failure(AttachmentImportError(message: "\(filename): unsupported file type."))
    }

    private static func convertImageFileToTemporaryPNG(at url: URL) -> URL? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return writeTemporaryPNG(from: image)
    }

    private static func saveConvertedPNG(
        _ pngURL: URL,
        storage: AttachmentStorageManager,
        filename: String
    ) async -> Result<DraftAttachment, AttachmentImportError> {
        do {
            let entity = try await storage.saveAttachment(from: pngURL, filename: filename, mimeType: "image/png")
            try? FileManager.default.removeItem(at: pngURL)
            return .success(
                DraftAttachment(
                    id: entity.id,
                    filename: entity.filename,
                    mimeType: entity.mimeType,
                    fileURL: entity.fileURL,
                    extractedText: nil
                )
            )
        } catch {
            return .failure(AttachmentImportError(message: "\(filename): failed to import (\(error.localizedDescription))."))
        }
    }

    private struct DraftAttachmentChip: View {
        let attachment: DraftAttachment
        let onRemove: () -> Void

        var body: some View {
            HStack(spacing: JinSpacing.small) {
                Group {
                    if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                    } else if attachment.isPDF {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 26, height: 26)

                Text(attachment.filename)
                    .font(.caption)
                    .lineLimit(1)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, JinSpacing.medium - 2)
            .padding(.vertical, JinSpacing.xSmall + 2)
            .jinSurface(.neutral, cornerRadius: JinRadius.medium)
            .onDrag {
                NSItemProvider(contentsOf: attachment.fileURL)
                    ?? NSItemProvider(object: attachment.fileURL as NSURL)
            }
            .contextMenu {
                Button {
                    NSWorkspace.shared.open(attachment.fileURL)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }

                Divider()

                if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([image])
                    } label: {
                        Label("Copy Image", systemImage: "doc.on.doc")
                    }
                }

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(attachment.fileURL.path, forType: .string)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
    
    private var selectedModelInfo: ModelInfo? {
        availableModels.first(where: { $0.id == conversationEntity.modelID })
    }

    private var lowerModelID: String {
        conversationEntity.modelID.lowercased()
    }

    private var isImageGenerationModelID: Bool {
        if lowerModelID.contains("-image") { return true }
        if providerType == .xai {
            return lowerModelID.contains("imagine-image")
                || lowerModelID.contains("grok-2-image")
        }
        return false
    }

    private var supportsNativePDF: Bool {
        guard !supportsMediaGenerationControl else { return false }
        if selectedModelInfo?.capabilities.contains(.nativePDF) == true {
            return true
        }

        switch providerType {
        case .openai:
            return lowerModelID.contains("gpt-5.2") || lowerModelID.contains("o3") || lowerModelID.contains("o4")
        case .anthropic:
            return lowerModelID.contains("-4-") || lowerModelID.contains("-4.")
        case .perplexity:
            return lowerModelID.contains("sonar")
        case .xai:
            return lowerModelID.contains("grok-4.1")
                || lowerModelID.contains("grok-4-1")
                || lowerModelID.contains("grok-4.2")
                || lowerModelID.contains("grok-4-2")
                || lowerModelID.contains("grok-5")
                || lowerModelID.contains("grok-6")
        case .gemini, .vertexai:
            return lowerModelID.contains("gemini-3")
        case .openaiCompatible, .openrouter, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsVision: Bool {
        selectedModelInfo?.capabilities.contains(.vision) == true
            || supportsImageGenerationControl
    }

    private var supportsImageGenerationControl: Bool {
        selectedModelInfo?.capabilities.contains(.imageGeneration) == true || isImageGenerationModelID
    }

    private var supportsMediaGenerationControl: Bool {
        supportsImageGenerationControl
    }

    private var supportsImageGenerationWebSearch: Bool {
        guard supportsImageGenerationControl else { return false }
        switch providerType {
        case .gemini, .vertexai:
            return !lowerModelID.contains("gemini-2.5-flash-image")
        case .perplexity:
            return false
        case .openai, .openaiCompatible, .openrouter, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsPDFProcessingControl: Bool {
        // Keep PDF preprocessing available for OCR/macOS extract even on media-generation models.
        true
    }

    private var supportsCurrentModelImageSizeControl: Bool {
        lowerModelID.contains("gemini-3-pro-image")
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
            if let format = controls.xaiImageGeneration?.responseFormat {
                return format == .url ? "URL" : "B64"
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
        if mistralOCRPluginEnabled {
            return .mistralOCR
        }
        if deepSeekOCRPluginEnabled {
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
        selectedModelInfo?.reasoningConfig
    }

    private var isReasoningEnabled: Bool {
        controls.reasoning?.enabled == true
    }

    private var isWebSearchEnabled: Bool {
        switch providerType {
        case .perplexity:
            return controls.webSearch?.enabled ?? true
        case .openai, .openaiCompatible, .openrouter, .anthropic, .xai, .deepseek, .fireworks, .cerebras, .gemini, .vertexai, .none:
            return controls.webSearch?.enabled == true
        }
    }

    private var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled ?? true
    }

    private var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    private var supportsWebSearchControl: Bool {
        if supportsMediaGenerationControl {
            if supportsImageGenerationControl {
                return supportsImageGenerationWebSearch
            }
            return false
        }

        // Provider-native web search, not MCP. Today: OpenAI, OpenRouter, Anthropic, xAI, Gemini API, Vertex AI.
        switch providerType {
        case .openai, .openrouter, .anthropic, .perplexity, .xai, .gemini, .vertexai:
            return true
        case .openaiCompatible, .deepseek, .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsMCPToolsControl: Bool {
        guard !supportsMediaGenerationControl else { return false }
        return selectedModelInfo?.capabilities.contains(.toolCalling) == true
    }

    private var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .gemini, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .perplexity:
            return "Reasoning: \(reasoningLabel)"
        case .openai, .openaiCompatible, .openrouter, .xai, .deepseek, .fireworks, .cerebras, .none:
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

    private var webSearchLabel: String {
        switch providerType {
        case .openai:
            return (controls.webSearch?.contextSize ?? .medium).displayName
        case .perplexity:
            return (controls.webSearch?.contextSize ?? .low).displayName
        case .xai:
            return webSearchSourcesLabel
        case .openaiCompatible, .openrouter, .anthropic, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
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

        switch providerType {
        case .openai:
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
        case .openaiCompatible, .openrouter, .anthropic, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            return "On"
        }
    }

    private var mcpToolsBadgeText: String? {
        guard supportsMCPToolsControl, isMCPToolsEnabled else { return nil }
        let count = selectedMCPServerIDs.count
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    private var eligibleMCPServers: [MCPServerConfigEntity] {
        mcpServers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var selectedMCPServerIDs: Set<String> {
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
        .contentShape(Rectangle())
        .onTapGesture {
            isModelPickerPresented = true
        }
        .help("Select model")
        .accessibilityLabel("Select model")
        .accessibilityAddTraits(.isButton)
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
            return
        }
        conversationEntity.modelID = models.first?.id ?? conversationEntity.modelID
        normalizeControlsForCurrentSelection()
    }

    private func setModel(_ modelID: String) {
        guard modelID != conversationEntity.modelID else { return }
        conversationEntity.modelID = modelID
        normalizeControlsForCurrentSelection()
    }

    private func setProviderAndModel(providerID: String, modelID: String) {
        guard providerID != conversationEntity.providerID || modelID != conversationEntity.modelID else { return }

        conversationEntity.providerID = providerID
        conversationEntity.modelID = modelID
        normalizeControlsForCurrentSelection()
    }

    private func preferredModelID(in models: [ModelInfo], providerID: String) -> String? {
        guard let provider = providers.first(where: { $0.id == providerID }),
              let type = ProviderType(rawValue: provider.typeRaw) else {
            return nil
        }

        switch type {
        case .openai:
            return models.first(where: { $0.id == "gpt-5.2" })?.id
        case .anthropic:
            return models.first(where: { $0.id == "claude-opus-4-6" })?.id
                ?? models.first(where: { $0.id == "claude-sonnet-4-5-20250929" })?.id
        case .perplexity:
            return models.first(where: { $0.id == "sonar-pro" })?.id
                ?? models.first(where: { $0.id == "sonar" })?.id
        case .deepseek:
            return models.first(where: { $0.id == "deepseek-chat" })?.id
                ?? models.first(where: { $0.id == "deepseek-reasoner" })?.id
        case .fireworks:
            return models.first(where: { $0.id.lowercased() == "fireworks/kimi-k2p5" || $0.id.lowercased() == "accounts/fireworks/models/kimi-k2p5" })?.id
                ?? models.first(where: { $0.id.lowercased() == "fireworks/glm-4p7" || $0.id.lowercased() == "accounts/fireworks/models/glm-4p7" })?.id
        case .cerebras:
            return models.first(where: { $0.id == "zai-glm-4.7" })?.id
        case .gemini:
            return models.first(where: { $0.id.lowercased().contains("gemini-3-pro") })?.id
                ?? models.first(where: { $0.id.lowercased().contains("gemini-3-flash") })?.id
        case .openaiCompatible, .openrouter, .xai, .vertexai:
            return nil
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func throttledScrollToBottom(proxy: ScrollViewProxy) {
        // Streaming updates can be very frequent; throttle auto-scroll to keep the UI responsive.
        guard isStreaming, streamingMessage != nil, isPinnedToBottom else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let minInterval: TimeInterval = 0.25
        guard now - lastStreamingAutoScrollUptime >= minInterval else { return }

        lastStreamingAutoScrollUptime = now
        scrollToBottom(proxy: proxy)
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

        var nextNormalizedMarkdownByKey: [MarkdownNormalizationCacheKey: String] = [:]
        nextNormalizedMarkdownByKey.reserveCapacity(cachedNormalizedMarkdownByKey.count)

        var messageEntitiesByID: [UUID: MessageEntity] = [:]
        messageEntitiesByID.reserveCapacity(ordered.count)

        var renderedItems: [MessageRenderItem] = []
        renderedItems.reserveCapacity(ordered.count)

        for entity in ordered {
            messageEntitiesByID[entity.id] = entity
            guard entity.role != "tool" else { continue }

            guard let message = try? entity.toDomain() else { continue }
            let renderedParts = renderedContentParts(
                messageID: entity.id,
                content: message.content,
                normalizationCache: &nextNormalizedMarkdownByKey
            )

            renderedItems.append(
                MessageRenderItem(
                    id: entity.id,
                    role: entity.role,
                    timestamp: entity.timestamp,
                    renderedContentParts: renderedParts,
                    toolCalls: message.toolCalls ?? [],
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
        cachedNormalizedMarkdownByKey = nextNormalizedMarkdownByKey
        cachedToolResultsByCallID = toolResultsByToolCallID(in: ordered)
        cachedMessagesVersion &+= 1
        lastCacheRebuildMessageCount = ordered.count
        lastCacheRebuildUpdatedAt = conversationEntity.updatedAt
    }

    private func renderedContentParts(
        messageID: UUID,
        content: [ContentPart],
        normalizationCache: inout [MarkdownNormalizationCacheKey: String]
    ) -> [RenderedMessageContentPart] {
        content.enumerated().map { index, part in
            guard case .text(let text) = part else {
                return RenderedMessageContentPart(part: part, normalizedMarkdownText: nil)
            }

            let key = MarkdownNormalizationCacheKey(messageID: messageID, partIndex: index, rawText: text)
            if let cached = cachedNormalizedMarkdownByKey[key] {
                normalizationCache[key] = cached
                return RenderedMessageContentPart(part: part, normalizedMarkdownText: cached)
            }

            let normalized = text.normalizingMathDelimitersForMarkdownView()
            normalizationCache[key] = normalized
            return RenderedMessageContentPart(part: part, normalizedMarkdownText: normalized)
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
        let attachmentsSnapshot = draftAttachments
        let askedAt = Date()

        if supportsMediaGenerationControl && messageTextSnapshot.isEmpty {
            errorMessage = "Image generation models require a text prompt."
            showingError = true
            return
        }

        messageText = ""
        draftAttachments = []

        isPreparingToSend = true
        prepareToSendStatus = nil

        let task = Task {
            do {
                let parts = try await buildUserMessageParts(
                    messageText: messageTextSnapshot,
                    attachments: attachmentsSnapshot
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
                    draftAttachments = attachmentsSnapshot
                }
            } catch {
                await MainActor.run {
                    isPreparingToSend = false
                    prepareToSendStatus = nil
                    prepareToSendTask = nil
                    messageText = messageTextSnapshot
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
        attachments: [DraftAttachment]
    ) async throws -> [ContentPart] {
        var parts: [ContentPart] = []
        parts.reserveCapacity(attachments.count + (messageText.isEmpty ? 0 : 1))

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
                    guard let decoded = decodeMistralOCRImageBase64(base64, imageID: id) else { continue }
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

                let normalized = normalizedDeepSeekOCRMarkdown(raw)
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

    private func normalizedDeepSeekOCRMarkdown(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let fenceCount = trimmed.components(separatedBy: "```").count - 1
        guard fenceCount == 2 else { return trimmed }

        guard let firstNewline = trimmed.firstIndex(of: "\n"),
              let closingRange = trimmed.range(of: "```", options: [.backwards]) else {
            return trimmed
        }

        let openingLine = String(trimmed[..<firstNewline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedOpening = openingLine == "```" || openingLine == "```markdown" || openingLine == "```md"
        guard allowedOpening else { return trimmed }

        let contentStart = trimmed.index(after: firstNewline)
        guard closingRange.lowerBound > contentStart else { return trimmed }

        let content = trimmed[contentStart..<closingRange.lowerBound]
        return String(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeMistralOCRImageBase64(_ raw: String, imageID: String) -> ImageContent? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("data:"),
           let commaIndex = trimmed.range(of: ","),
           let headerRange = trimmed.range(of: "data:") {
            let header = String(trimmed[headerRange.upperBound..<commaIndex.lowerBound])
            let base64 = String(trimmed[commaIndex.upperBound...])
            let mimeType = header.split(separator: ";").first.map(String.init)
                ?? mimeTypeForMistralImageID(imageID)
                ?? "image/png"
            guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else { return nil }
            return ImageContent(mimeType: mimeType, data: data, url: nil)
        }

        guard let data = Data(base64Encoded: trimmed, options: [.ignoreUnknownCharacters]) else { return nil }
        let mimeType = mimeTypeForMistralImageID(imageID) ?? sniffImageMimeType(from: data) ?? "image/png"
        return ImageContent(mimeType: mimeType, data: data, url: nil)
    }

    private func mimeTypeForMistralImageID(_ imageID: String) -> String? {
        let lower = imageID.lowercased()
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        return nil
    }

    private func sniffImageMimeType(from data: Data) -> String? {
        if data.count >= 3, data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.count >= 8, data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if data.count >= 12 {
            let riff = data.prefix(4)
            let webp = data.dropFirst(8).prefix(4)
            if riff == Data([0x52, 0x49, 0x46, 0x46]) && webp == Data([0x57, 0x45, 0x42, 0x50]) {
                return "image/webp"
            }
        }
        return nil
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

        let providerID = conversationEntity.providerID
        let modelID = conversationEntity.modelID
        let modelInfoSnapshot = selectedModelInfo
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

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let maxHistoryMessages = assistant?.maxHistoryMessages
        let modelContextWindow = modelInfoSnapshot?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let mcpServerConfigs = resolvedMCPServerConfigs(for: controlsToUse)
        let chatNamingTarget = resolvedChatNamingTarget()

        let task = Task.detached(priority: .userInitiated) {
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
                let mcpTools = try await MCPHub.shared.toolDefinitions(for: mcpServerConfigs)

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
                            assistantThinkingSegments.append(ThinkingBlockAccumulator(text: textDelta, signature: signature))
                            assistantPartRefs.append(.thinking(idx))

                        case .redacted(let data):
                            assistantPartRefs.append(.redacted(RedactedThinkingBlock(data: data)))
                        }
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

                    await MainActor.run {
                        streamingState.reset()
                    }

                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: modelID,
                        controls: controlsToUse,
                        tools: mcpTools,
                        streaming: true
                    )

                    // Streaming can yield very frequent deltas. Throttle how often we publish changes
                    // to SwiftUI to avoid re-layout/scrolling on every token.
                    var lastUIFlushUptime: TimeInterval = 0
                    var pendingTextDelta = ""
                    var pendingThinkingDelta = ""
                    var didAppendAnyThinkingText = false
                    var didShowRedactedThinkingPlaceholder = false
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
                                    didAppendAnyThinkingText = true
                                    pendingThinkingDelta.append(textDelta)
                                    streamedCharacterCount += textDelta.count
                                }
                            case .redacted:
                                if !didAppendAnyThinkingText && !didShowRedactedThinkingPlaceholder {
                                    didShowRedactedThinkingPlaceholder = true
                                    pendingThinkingDelta = "Thinking (redacted)"
                                }
                            }
                        case .toolCallStart(let call):
                            toolCallsByID[call.id] = call
                        case .toolCallDelta:
                            break
                        case .toolCallEnd(let call):
                            toolCallsByID[call.id] = call
                        case .messageEnd:
                            break
                        case .error(let err):
                            throw err
                        }

                        await flushStreamingUI()
                    }

                    await flushStreamingUI(force: true)

                    let toolCalls = Array(toolCallsByID.values)
                    let assistantParts = buildAssistantParts()
                    if !assistantParts.isEmpty || !toolCalls.isEmpty {
                        let assistantMessage = Message(
                            role: .assistant,
                            content: assistantParts,
                            toolCalls: toolCalls.isEmpty ? nil : toolCalls
                        )

                        await MainActor.run {
                            do {
                                let entity = try MessageEntity.fromDomain(assistantMessage)
                                entity.generatedProviderID = providerID
                                entity.generatedModelID = modelID
                                entity.generatedModelName = modelNameSnapshot
                                entity.conversation = conversationEntity
                                conversationEntity.messages.append(entity)
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
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

                    guard !toolCalls.isEmpty else { break }

                    await MainActor.run {
                        streamingState.reset()
                        streamingState.appendTextDelta("Running tools…")
                    }

                    var toolResults: [ToolResult] = []
                    var toolOutputLines: [String] = []

                    for call in toolCalls {
                        let callStart = Date()
                        do {
                            let result = try await MCPHub.shared.executeTool(functionName: call.name, arguments: call.arguments)
                            let duration = Date().timeIntervalSince(callStart)
                            let normalizedContent = normalizedToolResultContent(
                                result.text,
                                toolName: call.name,
                                isError: result.isError
                            )
                            toolResults.append(
                                ToolResult(
                                    toolCallID: call.id,
                                    toolName: call.name,
                                    content: normalizedContent,
                                    isError: result.isError,
                                    signature: call.signature,
                                    durationSeconds: duration
                                )
                            )

                            if result.isError {
                                toolOutputLines.append("Tool \(call.name) failed:\n\(normalizedContent)")
                            } else {
                                toolOutputLines.append("Tool \(call.name):\n\(normalizedContent)")
                            }
                        } catch {
                            let duration = Date().timeIntervalSince(callStart)
                            let normalizedError = normalizedToolResultContent(
                                error.localizedDescription,
                                toolName: call.name,
                                isError: true
                            )
                            let llmErrorContent = "Tool execution failed: \(normalizedError). You may retry this tool call with corrected arguments."
                            toolResults.append(
                                ToolResult(
                                    toolCallID: call.id,
                                    toolName: call.name,
                                    content: llmErrorContent,
                                    isError: true,
                                    signature: call.signature,
                                    durationSeconds: duration
                                )
                            )
                            toolOutputLines.append("Tool \(call.name) failed:\n\(llmErrorContent)")
                        }
                    }

                    let toolMessage = Message(role: .tool, content: toolOutputLines.isEmpty ? [] : [.text(toolOutputLines.joined(separator: "\n\n"))], toolResults: toolResults)
                    await MainActor.run {
                        do {
                            let entity = try MessageEntity.fromDomain(toolMessage)
                            entity.conversation = conversationEntity
                            conversationEntity.messages.append(entity)
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
            await MainActor.run {
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
                maxCharacters: 20
            )

            let normalized = ConversationTitleGenerator.normalizeTitle(title, maxCharacters: 20)
            guard !normalized.isEmpty else { return }
            conversationEntity.title = normalized
        } catch {
            if chatNamingMode == .firstRoundFixed {
                if conversationEntity.title == "New Chat" {
                    conversationEntity.title = fallbackTitleFromMessage(latestUser)
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

    @ViewBuilder
    private var reasoningMenuContent: some View {
        if let reasoningConfig = selectedReasoningConfig, reasoningConfig.type != .none {
            Button { setReasoningOff() } label: { menuItemLabel("Off", isSelected: !isReasoningEnabled) }

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
                        menuItemLabel("Configure thinking…", isSelected: isReasoningEnabled)
                    }
                } else {
                    switch providerType {
                    case .vertexai:
                        Button { setReasoningEffort(.minimal) } label: { menuItemLabel("Minimal", isSelected: isReasoningEnabled && controls.reasoning?.effort == .minimal) }
                        Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                        Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                        Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }

                    case .gemini:
                        if conversationEntity.modelID.lowercased().contains("gemini-3-pro") {
                            Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                            Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }
                        } else {
                            Button { setReasoningEffort(.minimal) } label: { menuItemLabel("Minimal", isSelected: isReasoningEnabled && controls.reasoning?.effort == .minimal) }
                            Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                            Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                            Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }
                        }

                    case .perplexity:
                        Button { setReasoningEffort(.minimal) } label: { menuItemLabel("Minimal", isSelected: isReasoningEnabled && controls.reasoning?.effort == .minimal) }
                        Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                        Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                        Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }

                    case .openai:
                        Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                        Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                        Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }
                        if isOpenAIGPT52SeriesModel {
                            Button { setReasoningEffort(.xhigh) } label: { menuItemLabel("Extreme", isSelected: isReasoningEnabled && controls.reasoning?.effort == .xhigh) }
                        }

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

                    case .fireworks:
                        Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                        Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                        Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }

                    case .openaiCompatible, .openrouter:
                        Button { setReasoningEffort(.low) } label: { menuItemLabel("Low", isSelected: isReasoningEnabled && controls.reasoning?.effort == .low) }
                        Button { setReasoningEffort(.medium) } label: { menuItemLabel("Medium", isSelected: isReasoningEnabled && controls.reasoning?.effort == .medium) }
                        Button { setReasoningEffort(.high) } label: { menuItemLabel("High", isSelected: isReasoningEnabled && controls.reasoning?.effort == .high) }

                    case .anthropic, .xai, .deepseek, .cerebras, .none:
                        EmptyView()
                    }
                }

                if supportsFireworksReasoningHistoryToggle {
                    Divider()
                    Text("Thinking history")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button { setFireworksReasoningHistory(nil) } label: { menuItemLabel("Default (model)", isSelected: fireworksReasoningHistory == nil) }
                    Button { setFireworksReasoningHistory("preserved") } label: { menuItemLabel("Preserved", isSelected: fireworksReasoningHistory == "preserved") }
                    Button { setFireworksReasoningHistory("interleaved") } label: { menuItemLabel("Interleaved", isSelected: fireworksReasoningHistory == "interleaved") }
                    Button { setFireworksReasoningHistory("disabled") } label: { menuItemLabel("Disabled", isSelected: fireworksReasoningHistory == "disabled") }
                    Button { setFireworksReasoningHistory("turn_level") } label: { menuItemLabel("Turn-level", isSelected: fireworksReasoningHistory == "turn_level") }
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
        guard providerType == .fireworks else { return false }
        let id = conversationEntity.modelID.lowercased()
        // Fireworks documents reasoning_history for Kimi K2 Instruct and GLM-4.7.
        return id.contains("kimi") || id.contains("glm-4p7")
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
            switch providerType {
            case .openai:
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
            case .openaiCompatible, .openrouter, .anthropic, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
                EmptyView()
            }
        }
    }

    private var mcpToolsEnabledBinding: Binding<Bool> {
        Binding(
            get: { controls.mcpTools?.enabled ?? true },
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

            Menu("Response format") {
                Button { updateXAIImageGeneration { $0.responseFormat = nil } } label: {
                    menuItemLabel("Default", isSelected: controls.xaiImageGeneration?.responseFormat == nil)
                }
                ForEach(XAIMediaResponseFormat.allCases, id: \.self) { format in
                    Button { updateXAIImageGeneration { $0.responseFormat = format } } label: {
                        menuItemLabel(format.displayName, isSelected: controls.xaiImageGeneration?.responseFormat == format)
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

    private var providerSpecificParamsBadgeText: String? {
        let count = controls.providerSpecific.count
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }

    private var providerSpecificParamsHelpText: String {
        let count = controls.providerSpecific.count
        if count == 0 { return "Provider Params: Default" }
        return "Provider Params: \(count) overridden"
    }

    @ViewBuilder
    private var providerSpecificParamsMenuContent: some View {
        Button("Edit JSON…") {
            openProviderSpecificParamsEditor()
        }

        if !controls.providerSpecific.isEmpty {
            Divider()
            Button("Clear", role: .destructive) {
                controls.providerSpecific = [:]
                persistControlsToConversation()
            }
        }
    }

    private func openProviderSpecificParamsEditor() {
        providerSpecificParamsError = nil
        providerSpecificParamsBaselineControls = controls

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let assistant = conversationEntity.assistant
        let controlsForDraft = GenerationControlsResolver.resolvedForRequest(
            base: controls,
            assistantTemperature: assistant?.temperature,
            assistantMaxOutputTokens: assistant?.maxOutputTokens
        )

        let draft = ProviderParamsJSONSync.makeDraft(
            providerType: providerType,
            modelID: conversationEntity.modelID,
            controls: controlsForDraft
        )

        if let data = try? encoder.encode(draft),
           let json = String(data: data, encoding: .utf8) {
            providerSpecificParamsDraft = json
        } else {
            providerSpecificParamsDraft = "{}"
        }

        // Force the editor to reset when reopening, but keep a stable ID while presenting.
        providerSpecificParamsEditorID = UUID()

        // Present on the next runloop tick so the TextEditor reliably picks up the draft text.
        DispatchQueue.main.async {
            showingProviderSpecificParamsSheet = true
        }
    }

    private var isProviderSpecificParamsDraftValid: Bool {
        let trimmed = providerSpecificParamsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONDecoder().decode([String: AnyCodable].self, from: data)) != nil
    }

    private func stripAssistantDefaultsFromControlsIfNeeded() {
        guard let baseline = providerSpecificParamsBaselineControls else { return }
        defer { providerSpecificParamsBaselineControls = nil }

        guard let assistant = conversationEntity.assistant else { return }

        if baseline.temperature == nil,
           let temperature = controls.temperature,
           abs(temperature - assistant.temperature) < 0.000_001 {
            controls.temperature = nil
        }

        if baseline.maxTokens == nil,
           let assistantMaxTokens = assistant.maxOutputTokens,
           controls.maxTokens == assistantMaxTokens {
            controls.maxTokens = nil
        }
    }

    @discardableResult
    private func applyProviderSpecificParamsDraft() -> Bool {
        let trimmed = providerSpecificParamsDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let decoded: [String: AnyCodable]
            if trimmed.isEmpty {
                decoded = [:]
            } else {
                guard let data = trimmed.data(using: .utf8) else {
                    throw NSError(domain: "ProviderParams", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 JSON."])
                }
                decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            }

            let remainder = ProviderParamsJSONSync.applyDraft(
                providerType: providerType,
                modelID: conversationEntity.modelID,
                draft: decoded,
                controls: &controls
            )
            controls.providerSpecific = remainder
            stripAssistantDefaultsFromControlsIfNeeded()
            normalizeControlsForCurrentSelection()
            persistControlsToConversation()
            providerSpecificParamsError = nil
            return true
        } catch {
            providerSpecificParamsError = error.localizedDescription
            return false
        }
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
        guard controlsToUse.mcpTools?.enabled ?? true else { return [] }

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

        let ttsProvider = TextToSpeechProvider(rawValue: defaults.string(forKey: AppPreferenceKeys.ttsProvider) ?? TextToSpeechProvider.openai.rawValue)
            ?? .openai
        let sttProvider = SpeechToTextProvider(rawValue: defaults.string(forKey: AppPreferenceKeys.sttProvider) ?? SpeechToTextProvider.groq.rawValue)
            ?? .groq

        let ttsAPIKeyPreferenceKey: String = {
            switch ttsProvider {
            case .elevenlabs:
                return AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:
                return AppPreferenceKeys.ttsOpenAIAPIKey
            case .groq:
                return AppPreferenceKeys.ttsGroqAPIKey
            }
        }()

        let sttAPIKeyPreferenceKey: String = {
            switch sttProvider {
            case .openai:
                return AppPreferenceKeys.sttOpenAIAPIKey
            case .groq:
                return AppPreferenceKeys.sttGroqAPIKey
            }
        }()

        let ttsKeyConfigured = hasStoredKey(ttsAPIKeyPreferenceKey)
        let sttKeyConfigured = hasStoredKey(sttAPIKeyPreferenceKey)

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

        await MainActor.run {
            mistralOCRConfigured = mistralConfigured
            deepSeekOCRConfigured = deepSeekConfigured
            textToSpeechConfigured = ttsConfigured
            speechToTextConfigured = sttKeyConfigured

            mistralOCRPluginEnabled = mistralEnabled
            deepSeekOCRPluginEnabled = deepSeekEnabled
            textToSpeechPluginEnabled = ttsEnabled
            speechToTextPluginEnabled = sttEnabled

            if !ttsEnabled {
                ttsPlaybackManager.stop()
            }
            if !sttEnabled {
                speechToTextManager.cancelAndCleanup()
            }
        }
    }

    private func currentSpeechToTextTranscriptionConfig() async throws -> SpeechToTextManager.TranscriptionConfig {
        let defaults = UserDefaults.standard
        let provider = SpeechToTextProvider(rawValue: defaults.string(forKey: AppPreferenceKeys.sttProvider) ?? SpeechToTextProvider.groq.rawValue)
            ?? .groq

        let apiKeyPreferenceKey: String = {
            switch provider {
            case .openai:
                return AppPreferenceKeys.sttOpenAIAPIKey
            case .groq:
                return AppPreferenceKeys.sttGroqAPIKey
            }
        }()

        let apiKey = (defaults.string(forKey: apiKeyPreferenceKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw SpeechExtensionError.speechToTextNotConfigured }

        func normalized(_ raw: String?) -> String? {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        switch provider {
        case .openai:
            let baseURLString = defaults.string(forKey: AppPreferenceKeys.sttOpenAIBaseURL) ?? OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
            guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SpeechExtensionError.invalidBaseURL(baseURLString)
            }

            let model = defaults.string(forKey: AppPreferenceKeys.sttOpenAIModel) ?? "gpt-4o-mini-transcribe"
            let translateToEnglish = defaults.bool(forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish)
            let language = normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAILanguage))
            let prompt = normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAIPrompt))
            let responseFormat = normalized(defaults.string(forKey: AppPreferenceKeys.sttOpenAIResponseFormat))
            let temperature = defaults.object(forKey: AppPreferenceKeys.sttOpenAITemperature) as? Double

            let timestampsJSON = defaults.string(forKey: AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON) ?? "[]"
            let timestamps = AppPreferences.decodeStringArrayJSON(timestampsJSON)
            let timestampGranularities = timestamps.isEmpty ? nil : timestamps

            return .openai(
                SpeechToTextManager.OpenAIConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model,
                    translateToEnglish: translateToEnglish,
                    language: language,
                    prompt: prompt,
                    responseFormat: responseFormat,
                    temperature: temperature,
                    timestampGranularities: timestampGranularities
                )
            )

        case .groq:
            let baseURLString = defaults.string(forKey: AppPreferenceKeys.sttGroqBaseURL) ?? GroqAudioClient.Constants.defaultBaseURL.absoluteString
            guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SpeechExtensionError.invalidBaseURL(baseURLString)
            }

            let model = defaults.string(forKey: AppPreferenceKeys.sttGroqModel) ?? "whisper-large-v3-turbo"
            let translateToEnglish = defaults.bool(forKey: AppPreferenceKeys.sttGroqTranslateToEnglish)
            let language = normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqLanguage))
            let prompt = normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqPrompt))
            let responseFormat = normalized(defaults.string(forKey: AppPreferenceKeys.sttGroqResponseFormat))
            let temperature = defaults.object(forKey: AppPreferenceKeys.sttGroqTemperature) as? Double

            let timestampsJSON = defaults.string(forKey: AppPreferenceKeys.sttGroqTimestampGranularitiesJSON) ?? "[]"
            let timestamps = AppPreferences.decodeStringArrayJSON(timestampsJSON)
            let timestampGranularities = timestamps.isEmpty ? nil : timestamps

            return .groq(
                SpeechToTextManager.GroqConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model,
                    translateToEnglish: translateToEnglish,
                    language: language,
                    prompt: prompt,
                    responseFormat: responseFormat,
                    temperature: temperature,
                    timestampGranularities: timestampGranularities
                )
            )
        }
    }

    private func toggleSpeakAssistantMessage(_ messageEntity: MessageEntity, text: String) {
        Task { @MainActor in
            guard textToSpeechPluginEnabled else { return }

            let defaults = UserDefaults.standard
            let provider = TextToSpeechProvider(rawValue: defaults.string(forKey: AppPreferenceKeys.ttsProvider) ?? TextToSpeechProvider.openai.rawValue)
                ?? .openai

            do {
                let config = try await currentTextToSpeechSynthesisConfig()
                ttsPlaybackManager.toggleSpeak(
                    messageID: messageEntity.id,
                    text: text,
                    config: config,
                    onError: { error in
                        errorMessage = textToSpeechErrorMessage(error, provider: provider)
                        showingError = true
                    }
                )
            } catch {
                errorMessage = textToSpeechErrorMessage(error, provider: provider)
                showingError = true
            }
        }
    }

    private func stopSpeakAssistantMessage(_ messageEntity: MessageEntity) {
        ttsPlaybackManager.stop(messageID: messageEntity.id)
    }

    private func textToSpeechErrorMessage(_ error: Error, provider: TextToSpeechProvider) -> String {
        if let llmError = error as? LLMError, case .authenticationFailed = llmError {
            switch provider {
            case .elevenlabs:
                return "\(llmError.localizedDescription)\n\nIf your ElevenLabs key uses endpoint scopes, enable access to /v1/text-to-speech."
            case .openai, .groq:
                return llmError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private func currentTextToSpeechSynthesisConfig() async throws -> TextToSpeechPlaybackManager.SynthesisConfig {
        let defaults = UserDefaults.standard
        let provider = TextToSpeechProvider(rawValue: defaults.string(forKey: AppPreferenceKeys.ttsProvider) ?? TextToSpeechProvider.openai.rawValue)
            ?? .openai

        let apiKeyPreferenceKey: String = {
            switch provider {
            case .elevenlabs:
                return AppPreferenceKeys.ttsElevenLabsAPIKey
            case .openai:
                return AppPreferenceKeys.ttsOpenAIAPIKey
            case .groq:
                return AppPreferenceKeys.ttsGroqAPIKey
            }
        }()

        let apiKey = (defaults.string(forKey: apiKeyPreferenceKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw SpeechExtensionError.textToSpeechNotConfigured }

        switch provider {
        case .openai:
            let baseURLString = defaults.string(forKey: AppPreferenceKeys.ttsOpenAIBaseURL) ?? OpenAIAudioClient.Constants.defaultBaseURL.absoluteString
            guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SpeechExtensionError.invalidBaseURL(baseURLString)
            }

            let model = defaults.string(forKey: AppPreferenceKeys.ttsOpenAIModel) ?? "gpt-4o-mini-tts"
            let voice = defaults.string(forKey: AppPreferenceKeys.ttsOpenAIVoice) ?? "alloy"
            let format = defaults.string(forKey: AppPreferenceKeys.ttsOpenAIResponseFormat) ?? "mp3"
            let speed = defaults.object(forKey: AppPreferenceKeys.ttsOpenAISpeed) as? Double
            let instructions = defaults.string(forKey: AppPreferenceKeys.ttsOpenAIInstructions)

            return .openai(
                TextToSpeechPlaybackManager.OpenAIConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model,
                    voice: voice,
                    responseFormat: format,
                    speed: speed,
                    instructions: instructions
                )
            )

        case .groq:
            let baseURLString = defaults.string(forKey: AppPreferenceKeys.ttsGroqBaseURL) ?? GroqAudioClient.Constants.defaultBaseURL.absoluteString
            guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SpeechExtensionError.invalidBaseURL(baseURLString)
            }

            let model = defaults.string(forKey: AppPreferenceKeys.ttsGroqModel) ?? "canopylabs/orpheus-v1-english"
            let voice = defaults.string(forKey: AppPreferenceKeys.ttsGroqVoice) ?? "troy"
            let format = defaults.string(forKey: AppPreferenceKeys.ttsGroqResponseFormat) ?? "wav"

            return .groq(
                TextToSpeechPlaybackManager.GroqConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: model,
                    voice: voice,
                    responseFormat: format
                )
            )

        case .elevenlabs:
            let baseURLString = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsBaseURL) ?? ElevenLabsTTSClient.Constants.defaultBaseURL.absoluteString
            guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw SpeechExtensionError.invalidBaseURL(baseURLString)
            }

            let voiceId = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsVoiceID) ?? ""
            guard !voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SpeechExtensionError.missingElevenLabsVoice
            }

            let modelId = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsModelID)
            let outputFormat = defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsOutputFormat)

            let optimize = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsOptimizeStreamingLatency) as? Int
            let enableLogging = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsEnableLogging) as? Bool

            let stability = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStability) as? Double
            let similarity = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsSimilarityBoost) as? Double
            let style = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsStyle) as? Double
            let speakerBoost = defaults.object(forKey: AppPreferenceKeys.ttsElevenLabsUseSpeakerBoost) as? Bool

            let voiceSettings = ElevenLabsTTSClient.VoiceSettings(
                stability: stability,
                similarityBoost: similarity,
                style: style,
                useSpeakerBoost: speakerBoost
            )

            return .elevenlabs(
                TextToSpeechPlaybackManager.ElevenLabsConfig(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    voiceId: voiceId,
                    modelId: modelId,
                    outputFormat: outputFormat,
                    optimizeStreamingLatency: optimize,
                    enableLogging: enableLogging,
                    voiceSettings: voiceSettings
                )
            )
        }
    }

    private func persistControlsToConversation() {
        do {
            conversationEntity.modelConfigData = try JSONEncoder().encode(controls)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func setReasoningOff() {
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
            if providerType == .openai, reasoning.summary == nil {
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
            return "Opus 4.6 uses adaptive thinking. Choose an effort level, then set a max output limit."
        }
        return "Claude 4.5 uses budget-based thinking. Set budget tokens and max output tokens together."
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

    @ViewBuilder
    private func thinkingControlRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: JinSpacing.medium) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            control()
        }
    }

    @ViewBuilder
    private func thinkingTokenField(placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder))
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 170)
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
            if providerType == .openai, (reasoning.effort ?? ReasoningEffort.none) == ReasoningEffort.none {
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

    private var isOpenAIGPT52SeriesModel: Bool {
        guard providerType == .openai else { return false }
        return conversationEntity.modelID.hasPrefix("gpt-5.2")
    }

    private func defaultWebSearchControls(enabled: Bool) -> WebSearchControls {
        guard enabled else { return WebSearchControls(enabled: false) }

        switch providerType {
        case .openai:
            return WebSearchControls(enabled: true, contextSize: .medium, sources: nil)
        case .perplexity:
            // Perplexity defaults `search_context_size` to `low` when omitted.
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        case .xai:
            return WebSearchControls(enabled: true, contextSize: nil, sources: [.web])
        case .openaiCompatible, .openrouter, .anthropic, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        }
    }

    private func ensureValidWebSearchDefaultsIfEnabled() {
        guard controls.webSearch?.enabled == true else { return }
        switch providerType {
        case .openai:
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
        case .openaiCompatible, .openrouter, .anthropic, .gemini, .vertexai, .deepseek, .fireworks, .cerebras, .none:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
        }
    }

    private func normalizeControlsForCurrentSelection() {
        // Ensure the stored controls remain valid when switching provider/model.
        let originalData = (try? JSONEncoder().encode(controls)) ?? Data()

        if supportsMediaGenerationControl {
            if !supportsReasoningControl {
                controls.reasoning = nil
            }
            if !supportsWebSearchControl {
                controls.webSearch = nil
            }
            controls.mcpTools = nil
        }

        // Reasoning: enforce model's reasoning config expectations.
        if supportsReasoningControl, let reasoningConfig = selectedReasoningConfig {
            switch reasoningConfig.type {
            case .effort:
                if providerType != .anthropic,
                   controls.reasoning?.enabled == true,
                   controls.reasoning?.effort == nil {
                    updateReasoning { $0.effort = reasoningConfig.defaultEffort ?? .medium }
                }
                if providerType != .anthropic {
                    controls.reasoning?.budgetTokens = nil
                }
                if providerType == .openai,
                   controls.reasoning?.enabled == true,
                   (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
                   controls.reasoning?.summary == nil {
                    controls.reasoning?.summary = .auto
                }
                if providerType == .anthropic {
                    normalizeAnthropicReasoningAndMaxTokens()
                }

            case .budget:
                if controls.reasoning?.enabled == true, controls.reasoning?.budgetTokens == nil {
                    updateReasoning { $0.budgetTokens = reasoningConfig.defaultBudget ?? 2048 }
                }
                controls.reasoning?.effort = nil
                controls.reasoning?.summary = nil
            case .toggle:
                if controls.reasoning == nil {
                    // For toggle-only providers (e.g. Cerebras GLM), default to “On” so the UI and request match.
                    controls.reasoning = ReasoningControls(enabled: true)
                }
                controls.reasoning?.effort = nil
                controls.reasoning?.budgetTokens = nil
                controls.reasoning?.summary = nil
            case .none:
                controls.reasoning = nil
            }
        } else if !supportsReasoningControl {
            controls.reasoning = nil
        }

        if supportsReasoningControl {
            // OpenAI: only GPT-5.2 supports xhigh.
            if providerType == .openai, controls.reasoning?.effort == .xhigh, !isOpenAIGPT52SeriesModel {
                controls.reasoning?.effort = .high
            }

            if providerType == .anthropic {
                normalizeAnthropicReasoningAndMaxTokens()
            }

            // Gemini 3 Pro: only supports low/high thinking levels.
            if providerType == .gemini,
               conversationEntity.modelID.lowercased().contains("gemini-3-pro"),
               let effort = controls.reasoning?.effort {
                switch effort {
                case .none:
                    break
                case .minimal:
                    controls.reasoning?.effort = .low
                case .low:
                    break
                case .medium:
                    controls.reasoning?.effort = .high
                case .high:
                    break
                case .xhigh:
                    controls.reasoning?.effort = .high
                }
            }
        }

        if supportsWebSearchControl {
            if controls.webSearch?.enabled == true {
                ensureValidWebSearchDefaultsIfEnabled()
            }
        } else {
            controls.webSearch = nil
        }

        if !supportsReasoningControl, providerType == .anthropic {
            controls.maxTokens = nil
        }

        if providerType == .anthropic,
           controls.maxTokens != nil,
           controls.reasoning?.enabled != true {
            controls.maxTokens = nil
        }

        if supportsImageGenerationControl {
            if providerType == .xai {
                controls.imageGeneration = nil

                if var xaiImage = controls.xaiImageGeneration {
                    // Drop deprecated fields so persisted controls match current xAI API support.
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

        let newData = (try? JSONEncoder().encode(controls)) ?? Data()
        if newData != originalData {
            persistControlsToConversation()
        }
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

// MARK: - Message Row & Content Views

struct MessageRenderItem: Identifiable {
    let id: UUID
    let role: String
    let timestamp: Date
    let renderedContentParts: [RenderedMessageContentPart]
    let toolCalls: [ToolCall]
    let assistantModelLabel: String?
    let copyText: String
    let canEditUserMessage: Bool

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isTool: Bool { role == "tool" }
}

struct RenderedMessageContentPart {
    let part: ContentPart
    let normalizedMarkdownText: String?
}

private struct MarkdownNormalizationCacheKey: Hashable {
    let messageID: UUID
    let partIndex: Int

    private let textLength: Int
    private let textHash: Int

    init(messageID: UUID, partIndex: Int, rawText: String) {
        self.messageID = messageID
        self.partIndex = partIndex
        self.textLength = rawText.utf8.count

        var hasher = Hasher()
        hasher.combine(rawText)
        self.textHash = hasher.finalize()
    }
}

struct MessageRow: View {
    let item: MessageRenderItem
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let providerIconID: String?
    let toolResultsByCallID: [String: ToolResult]
    let actionsEnabled: Bool
    let textToSpeechEnabled: Bool
    let textToSpeechConfigured: Bool
    let textToSpeechIsGenerating: Bool
    let textToSpeechIsPlaying: Bool
    let textToSpeechIsPaused: Bool
    let onToggleSpeakAssistantMessage: (UUID, String) -> Void
    let onStopSpeakAssistantMessage: (UUID) -> Void
    let onRegenerate: (UUID) -> Void
    let onEditUserMessage: (UUID) -> Void
    let editingUserMessageID: UUID?
    let editingUserMessageText: Binding<String>
    let editingUserMessageFocused: Binding<Bool>
    let onSubmitUserEdit: (UUID) -> Void
    let onCancelUserEdit: () -> Void

    var body: some View {
        let isUser = item.isUser
        let isAssistant = item.isAssistant
        let isTool = item.isTool
        let isEditingUserMessage = isUser && editingUserMessageID == item.id
        let assistantModelLabel = item.assistantModelLabel
        let copyText = item.copyText
        let showsCopyButton = (isUser || isAssistant) && !copyText.isEmpty
        let canEditUserMessage = item.canEditUserMessage

        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 0)
            }

            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    headerView(isUser: isUser, isTool: isTool, assistantModelLabel: assistantModelLabel)

                    VStack(alignment: .leading, spacing: 8) {
                        if isEditingUserMessage {
                            DroppableTextEditor(
                                text: editingUserMessageText,
                                isDropTargeted: .constant(false),
                                isFocused: editingUserMessageFocused,
                                font: NSFont.preferredFont(forTextStyle: .body),
                                onDropFileURLs: { _ in false },
                                onDropImages: { _ in false },
                                onSubmit: { onSubmitUserEdit(item.id) },
                                onCancel: {
                                    onCancelUserEdit()
                                    return true
                                }
                            )
                            .frame(minHeight: 36, maxHeight: 200)
                        } else {
                            ForEach(Array(item.renderedContentParts.enumerated()), id: \.offset) { _, rendered in
                                ContentPartView(part: rendered.part, normalizedMarkdownText: rendered.normalizedMarkdownText)
                            }

                            if !item.toolCalls.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(item.toolCalls) { call in
                                        ToolCallView(
                                            toolCall: call,
                                            toolResult: toolResultsByCallID[call.id]
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(JinSpacing.medium)
                    .jinSurface(bubbleBackground(isUser: isUser, isTool: isTool), cornerRadius: JinRadius.medium)

                    if isUser || isAssistant {
                        footerView(
                            isUser: isUser,
                            isAssistant: isAssistant,
                            isEditingUserMessage: isEditingUserMessage,
                            showsCopyButton: showsCopyButton,
                            copyText: copyText,
                            canEditUserMessage: canEditUserMessage
                        )
                        .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 16)

            if !isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func headerView(isUser: Bool, isTool: Bool, assistantModelLabel: String?) -> some View {
        if isUser {
            EmptyView()
        } else {
            HStack(spacing: JinSpacing.small - 2) {
                if !isTool {
                    ProviderBadgeIcon(iconID: providerIconID)
                }

                if isTool {
                    Image(systemName: "hammer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Tool Output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if assistantDisplayName != "Assistant" {
                    Text(assistantDisplayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                if !isTool, let label = assistantModelLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    Text(label)
                        .jinTagStyle()
                }
            }
            .padding(.horizontal, JinSpacing.medium)
            .padding(.bottom, 2) // Added small bottom padding to separate from bubble
        }
    }

    @ViewBuilder
    private func footerView(isUser: Bool, isAssistant: Bool, isEditingUserMessage: Bool, showsCopyButton: Bool, copyText: String, canEditUserMessage: Bool) -> some View {
        if isAssistant {
            HStack(spacing: JinSpacing.small) {
                if showsCopyButton {
                    CopyToPasteboardButton(text: copyText, helpText: "Copy message", useProminentStyle: false)
                        .accessibilityLabel("Copy message")
                        .disabled(!actionsEnabled)
                }

                if textToSpeechEnabled {
                    Button {
                        onToggleSpeakAssistantMessage(item.id, copyText)
                    } label: {
                        if textToSpeechIsGenerating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: textToSpeechPrimarySystemName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(textToSpeechHelpText)
                    .disabled(!actionsEnabled || copyText.isEmpty || !textToSpeechConfigured)

                    if textToSpeechIsActive {
                        actionIconButton(systemName: "stop.circle", helpText: textToSpeechStopHelpText) {
                            onStopSpeakAssistantMessage(item.id)
                        }
                        .disabled(!actionsEnabled)
                    }
                }

                actionIconButton(systemName: "arrow.clockwise", helpText: "Regenerate") {
                    onRegenerate(item.id)
                }
                .disabled(!actionsEnabled)

                Spacer(minLength: 0)

                Text(formattedTimestamp(item.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        } else if isUser {
            HStack(spacing: JinSpacing.small) {
                if isEditingUserMessage {
                    actionIconButton(systemName: "xmark", helpText: "Cancel editing") {
                        onCancelUserEdit()
                    }
                    .disabled(!actionsEnabled)

                    actionIconButton(systemName: "paperplane", helpText: "Resend") {
                        onSubmitUserEdit(item.id)
                    }
                    .disabled(!actionsEnabled)
                } else {
                    if showsCopyButton {
                        CopyToPasteboardButton(text: copyText, helpText: "Copy message", useProminentStyle: false)
                            .accessibilityLabel("Copy message")
                            .disabled(!actionsEnabled)
                    }

                    actionIconButton(systemName: "arrow.clockwise", helpText: "Regenerate") {
                        onRegenerate(item.id)
                    }
                    .disabled(!actionsEnabled)

                    if canEditUserMessage {
                        actionIconButton(systemName: "pencil", helpText: "Edit") {
                            onEditUserMessage(item.id)
                        }
                        .disabled(!actionsEnabled)
                    }
                }
            }
        }
    }

    private func actionIconButton(systemName: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var textToSpeechIsActive: Bool {
        textToSpeechIsGenerating || textToSpeechIsPlaying || textToSpeechIsPaused
    }

    private var textToSpeechPrimarySystemName: String {
        if textToSpeechIsPlaying {
            return "pause.circle"
        }
        if textToSpeechIsPaused {
            return "play.circle"
        }
        return "speaker.wave.2"
    }

    private var textToSpeechHelpText: String {
        if !textToSpeechConfigured {
            return "Configure Text to Speech in Settings → Plugins → Text to Speech"
        }
        if textToSpeechIsGenerating {
            return "Generating speech…"
        }
        if textToSpeechIsPlaying {
            return "Pause playback"
        }
        if textToSpeechIsPaused {
            return "Resume playback"
        }
        return "Speak"
    }

    private var textToSpeechStopHelpText: String {
        if textToSpeechIsGenerating {
            return "Stop generating speech"
        }
        return "Stop playback"
    }

    private func formattedTimestamp(_ timestamp: Date) -> String {
        let calendar = Calendar.current
        let time = timestamp.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(timestamp) {
            return time
        }
        if calendar.isDateInYesterday(timestamp) {
            return "Yesterday \(time)"
        }

        let day = timestamp.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(day) \(time)"
    }

    private func bubbleBackground(isUser: Bool, isTool: Bool) -> JinSurfaceVariant {
        if isTool { return .tool }
        if isUser { return .accent }
        return .neutral
    }
}

private struct ProviderBadgeIcon: View {
    let iconID: String?

    var body: some View {
        ProviderIconView(iconID: iconID, fallbackSystemName: "network", size: 14)
            .frame(width: 14, height: 14)
    }
}

private struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BottomSentinelMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LoadEarlierMessagesRow: View {
    let hiddenCount: Int
    let pageSize: Int
    let onLoad: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button {
                onLoad()
            } label: {
                let count = min(pageSize, hiddenCount)
                Text("Load \(count) earlier messages (\(hiddenCount) hidden)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

struct ContentPartView: View {
    let part: ContentPart
    let normalizedMarkdownText: String?

    var body: some View {
        switch part {
        case .text(let text):
            if let normalizedMarkdownText {
                MessageTextView(normalizedMarkdownText: normalizedMarkdownText)
            } else {
                MessageTextView(text: text)
            }

        case .thinking(let thinking):
            ThinkingBlockView(thinking: thinking)

        case .redactedThinking(let redacted):
            RedactedThinkingBlockView(redactedThinking: redacted)

        case .image(let image):
            let fileURL = (image.url?.isFileURL == true) ? image.url : nil

            if let data = image.data, let nsImage = NSImage(data: data) {
                renderedImage(nsImage, fileURL: fileURL)
            } else if let fileURL, let nsImage = NSImage(contentsOf: fileURL) {
                renderedImage(nsImage, fileURL: fileURL)
            } else if let url = image.url {
                Link(url.absoluteString, destination: url)
                    .font(.caption)
            }

        case .video(let video):
            renderedVideo(video)

        case .file(let file):
            let row = HStack {
                Image(systemName: "doc")
                Text(file.filename)
            }
            .padding(JinSpacing.small)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)

            if let url = file.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    row
                }
                .buttonStyle(.plain)
                .help("Open \(file.filename)")
                .onDrag {
                    NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
                }
                .contextMenu {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(url.path, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(file.filename, forType: .string)
                    } label: {
                        Label("Copy Filename", systemImage: "doc.on.doc")
                    }

                    if let extracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !extracted.isEmpty {
                        Divider()

                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(extracted, forType: .string)
                        } label: {
                            Label("Copy Extracted Text", systemImage: "doc.on.doc")
                        }
                    }
                }
            } else {
                row
                    .contextMenu {
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(file.filename, forType: .string)
                        } label: {
                            Label("Copy Filename", systemImage: "doc.on.doc")
                        }

                        if let extracted = file.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !extracted.isEmpty {
                            Divider()

                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(extracted, forType: .string)
                            } label: {
                                Label("Copy Extracted Text", systemImage: "doc.on.doc")
                            }
                        }
                    }
            }

        case .audio:
            Label("Audio content", systemImage: "waveform")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }

    @ViewBuilder
    private func renderedVideo(_ video: VideoContent) -> some View {
        if let fileURL = video.url, fileURL.isFileURL {
            VideoPlayer(player: AVPlayer(url: fileURL))
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                .contextMenu {
                    Button {
                        NSWorkspace.shared.open(fileURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(fileURL.path, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                }
        } else if let url = video.url {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                .contextMenu {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }

                    Divider()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(url.absoluteString, forType: .string)
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                }
        } else if let data = video.data {
            Label("Video data (\(data.count) bytes)", systemImage: "video")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        } else {
            Label("Video", systemImage: "video")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }

    @ViewBuilder
    private func renderedImage(_ image: NSImage, fileURL: URL?) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 500)
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .onDrag {
                if let fileURL {
                    return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
                }
                return NSItemProvider(object: image)
            }
            .contextMenu {
                if let fileURL {
                    Button {
                        NSWorkspace.shared.open(fileURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()
                }

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                } label: {
                    Label("Copy Image", systemImage: "doc.on.doc")
                }

                if let fileURL {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(fileURL.path, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                }
            }
    }
}


struct ToolCallView: View {
    let toolCall: ToolCall
    let toolResult: ToolResult?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(spacing: JinSpacing.small) {
                Image(systemName: "hammer")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text(displayTitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                statusPill

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(JinIconButtonStyle())
            }

            if !isExpanded, let argumentSummary {
                Text("-> \(argumentSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: JinSpacing.medium - 2) {
                    if let argsString = formattedArgumentsJSON {
                        ToolCallCodeBlockView(title: "Arguments", text: argsString)
                    } else {
                        ToolCallCodeBlockView(title: "Arguments", text: "{}")
                    }

                    if let toolResult {
                        ToolCallCodeBlockView(title: toolResult.isError ? "Error" : "Output", text: toolResult.content)
                    } else {
                        Text("Waiting for tool result…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let signature = toolCall.signature, !signature.isEmpty {
                        ToolCallCodeBlockView(title: "Signature", text: signature)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, JinSpacing.medium)
        .padding(.vertical, JinSpacing.medium - 2)
        .jinSurface(.subtleStrong, cornerRadius: JinRadius.medium)
    }

    private var formattedArgumentsJSON: String? {
        let raw = toolCall.arguments.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(raw) else { return nil }
        guard let argsJSON = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]),
              let argsString = String(data: argsJSON, encoding: .utf8) else {
            return nil
        }
        return argsString
    }

    private var displayTitle: String {
        let (serverID, toolName) = splitFunctionName(toolCall.name)
        if serverID.isEmpty { return toolName }
        return "\(serverID) · \(toolName)"
    }

    @ViewBuilder
    private var statusPill: some View {
        let status = resolvedStatus
        let foreground: Color = {
            switch status {
            case .running: return .secondary
            case .success: return .green
            case .error: return .red
            }
        }()

        HStack(spacing: 6) {
            switch status {
            case .running:
                ProgressView()
                    .scaleEffect(0.6)
                Text("Running")
            case .success:
                Image(systemName: "checkmark")
                Text("Success")
            case .error:
                Image(systemName: "xmark")
                Text("Error")
            }

            if let durationText {
                Text(durationText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .jinTagStyle(foreground: foreground)
    }

    private var durationText: String? {
        guard let seconds = toolResult?.durationSeconds, seconds > 0 else { return nil }
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return "\(Int(seconds.rounded()))s"
    }

    private var resolvedStatus: ToolCallStatus {
        guard let toolResult else { return .running }
        return toolResult.isError ? .error : .success
    }

    private enum ToolCallStatus {
        case running
        case success
        case error
    }

    private func splitFunctionName(_ name: String) -> (serverID: String, toolName: String) {
        guard let range = name.range(of: "__") else { return ("", name) }
        let serverID = String(name[..<range.lowerBound])
        let toolName = String(name[range.upperBound...])
        return (serverID, toolName.isEmpty ? name : toolName)
    }

    private var argumentSummary: String? {
        let raw = toolCall.arguments.mapValues { $0.value }
        guard !raw.isEmpty else { return nil }

        // Common argument names used by popular MCP servers
        let preferredKeys = ["query", "q", "url", "input", "text"]
        for key in preferredKeys {
            if let value = raw[key] as? String {
                return oneLine(value, maxLength: 200)
            }
        }

        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return oneLine(json, maxLength: 200)
    }

    private func oneLine(_ string: String, maxLength: Int) -> String {
        let condensed = string
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard condensed.count > maxLength else { return condensed }
        return String(condensed.prefix(maxLength - 1)) + "…"
    }
}

private struct ToolCallCodeBlockView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small - 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(JinSpacing.medium - 2)
            .jinSurface(.subtle, cornerRadius: JinRadius.small)
        }
    }
}

private struct ChunkedTextView: View {
    let chunks: [String]
    let font: Font
    let allowsTextSelection: Bool

    var body: some View {
        Group {
            if allowsTextSelection {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks.indices, id: \.self) { idx in
                        Text(verbatim: chunks[idx])
                            .font(font)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks.indices, id: \.self) { idx in
                        Text(verbatim: chunks[idx])
                            .font(font)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private enum StreamedAssistantPartRef {
    case text(Int)
    case image(Int)
    case video(Int)
    case thinking(Int)
    case redacted(RedactedThinkingBlock)
}

private struct ThinkingBlockAccumulator {
    var text: String
    var signature: String?
}

struct StreamingMessageView: View {
    @ObservedObject var state: StreamingMessageState
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let modelLabel: String?
    let providerIconID: String?
    let onContentUpdate: () -> Void

    var body: some View {
        let showsCopyButton = state.hasVisibleText

        HStack(alignment: .top, spacing: 0) {
            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: JinSpacing.small - 2) {
                    HStack(spacing: JinSpacing.small - 2) {
                        ProviderBadgeIcon(iconID: providerIconID)
                        
                        if assistantDisplayName != "Assistant" {
                            Text(assistantDisplayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }

                        if let label = modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                            Text(label)
                                .jinTagStyle()
                        }
                    }
                    .padding(.horizontal, JinSpacing.medium)
                    .padding(.bottom, 2)

                    VStack(alignment: .leading, spacing: JinSpacing.small) {
                        if !state.thinkingChunks.isEmpty {
                            DisclosureGroup(isExpanded: .constant(true)) {
                                ChunkedTextView(
                                    chunks: state.thinkingChunks,
                                    font: .system(.caption, design: .monospaced),
                                    allowsTextSelection: false
                                )
                                    .foregroundStyle(.secondary)
                                    .padding(JinSpacing.small)
                                    .background(JinSemanticColor.textSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                            } label: {
                                HStack {
                                    ProgressView().scaleEffect(0.5)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !state.textChunks.isEmpty {
                            ChunkedTextView(chunks: state.textChunks, font: .body, allowsTextSelection: false)
                        } else if state.thinkingChunks.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(JinSpacing.medium)
                    .jinSurface(.neutral, cornerRadius: JinRadius.medium)

                    if showsCopyButton {
                        HStack {
                            CopyToPasteboardButton(text: state.textContent, helpText: "Copy message", useProminentStyle: false)
                                .accessibilityLabel("Copy message")
                            Spacer(minLength: 0)
                        }
                        .padding(.top, JinSpacing.xSmall - 2)
                    }
                }
            }
            .padding(.horizontal, JinSpacing.large)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, JinSpacing.small)
        .onChange(of: state.renderTick) { _, _ in
            onContentUpdate()
        }
    }
}

final class StreamingMessageState: ObservableObject {
    private static let maxChunkSize = 2048

    @Published private(set) var textChunks: [String] = []
    @Published private(set) var thinkingChunks: [String] = []
    @Published private(set) var renderTick: Int = 0
    @Published private(set) var hasVisibleText: Bool = false

    private var textStorage = ""
    private var thinkingStorage = ""

    var textContent: String { textStorage }
    var thinkingContent: String { thinkingStorage }

    func reset() {
        textStorage = ""
        thinkingStorage = ""
        textChunks = []
        thinkingChunks = []
        hasVisibleText = false
        renderTick = 0
    }

    func appendDeltas(textDelta: String, thinkingDelta: String) {
        var didMutate = false

        if !textDelta.isEmpty {
            textStorage.append(textDelta)
            if !hasVisibleText,
               textDelta.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil {
                hasVisibleText = true
            }
            appendDelta(textDelta, to: &textChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
        }

        if !thinkingDelta.isEmpty {
            thinkingStorage.append(thinkingDelta)
            appendDelta(thinkingDelta, to: &thinkingChunks, maxChunkSize: Self.maxChunkSize)
            didMutate = true
        }

        if didMutate {
            renderTick &+= 1
        }
    }

    func appendTextDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        appendDeltas(textDelta: delta, thinkingDelta: "")
    }

    func appendThinkingDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        appendDeltas(textDelta: "", thinkingDelta: delta)
    }

    private func appendDelta(_ delta: String, to chunks: inout [String], maxChunkSize: Int) {
        if chunks.isEmpty {
            chunks.append(delta)
        } else {
            chunks[chunks.count - 1].append(delta)
        }

        while let lastChunk = chunks.last, lastChunk.count > maxChunkSize {
            let maxIndex = lastChunk.index(lastChunk.startIndex, offsetBy: maxChunkSize)
            let candidate = lastChunk[..<maxIndex]

            let splitIndex = candidate.lastIndex(of: "\n").map { lastChunk.index(after: $0) } ?? maxIndex
            let prefix = String(lastChunk[..<splitIndex])
            let suffix = String(lastChunk[splitIndex...])

            chunks[chunks.count - 1] = prefix
            if !suffix.isEmpty {
                chunks.append(suffix)
            }
        }
    }
}
