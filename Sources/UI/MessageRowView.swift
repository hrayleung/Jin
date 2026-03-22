import SwiftUI
import AppKit
import Foundation

// MARK: - User Message MCP Badge Row

struct UserMessageMCPBadgeRow: View {
    let serverNames: [String]

    var body: some View {
        HStack(spacing: JinSpacing.xSmall) {
            Image(systemName: "hammer")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(serverNames, id: \.self) { name in
                Text(name)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
    }
}

// MARK: - Render Models

struct MessageRenderItem: Identifiable, Sendable {
    let id: UUID
    let contextThreadID: UUID?
    let role: String
    let timestamp: Date
    let renderedBlocks: [RenderedMessageBlock]
    let toolCalls: [ToolCall]
    let searchActivities: [SearchActivity]
    let codeExecutionActivities: [CodeExecutionActivity]
    let codexToolActivities: [CodexToolActivity]
    let agentToolActivities: [CodexToolActivity]
    let assistantModelLabel: String?
    let assistantProviderIconID: String?
    let responseMetrics: ResponseMetrics?
    let copyText: String
    let canEditUserMessage: Bool
    let canDeleteResponse: Bool
    let perMessageMCPServerNames: [String]

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isTool: Bool { role == "tool" }
}

// MARK: - Message Row

struct MessageRow: View {
    let item: MessageRenderItem
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let providerIconID: String?
    let deferCodeHighlightUpgrade: Bool
    let toolResultsByCallID: [String: ToolResult]
    let textToSpeechEnabled: Bool
    let textToSpeechConfigured: Bool
    let textToSpeechIsGenerating: Bool
    let textToSpeechIsPlaying: Bool
    let textToSpeechIsPaused: Bool
    let onToggleSpeakAssistantMessage: (UUID, String) -> Void
    let onStopSpeakAssistantMessage: (UUID) -> Void
    let onRegenerate: (UUID) -> Void
    let onEditUserMessage: (UUID) -> Void
    let onDeleteMessage: (UUID) -> Void
    let onDeleteResponse: (UUID) -> Void
    let editingUserMessageID: UUID?
    let editingUserMessageText: Binding<String>
    let editingUserMessageFocused: Binding<Bool>
    let onSubmitUserEdit: (UUID) -> Void
    let onCancelUserEdit: () -> Void
    let editSlashCommand: EditSlashCommandContext
    let onOpenArtifact: (RenderedArtifactVersion, UUID?) -> Void
    let onActivate: (() -> Void)?
    @State private var isResponseMetricsPopoverPresented = false
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteAction: DeleteAction?
    private enum DeleteAction { case message, response }

    var body: some View {
        let isUser = item.isUser
        let isAssistant = item.isAssistant
        let isTool = item.isTool
        let isEditingUserMessage = isUser && editingUserMessageID == item.id
        let assistantModelLabel = item.assistantModelLabel
        let copyText = item.copyText
        let showsCopyButton = (isUser || isAssistant) && !copyText.isEmpty
        let canEditUserMessage = item.canEditUserMessage
        let canDeleteResponse = item.canDeleteResponse
        let visibleToolCalls = item.toolCalls.filter { call in
            !BuiltinSearchToolHub.isBuiltinSearchFunctionName(call.name)
            && !isGoogleProviderNativeToolName(call.name)
            && !AgentToolHub.isAgentFunctionName(call.name)
        }

        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer(minLength: 0)
            }

            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    headerView(isUser: isUser, isTool: isTool, assistantModelLabel: assistantModelLabel)

                    VStack(alignment: .leading, spacing: 8) {
                        if isEditingUserMessage {
                            if editSlashCommand.isActive {
                                SlashCommandMCPPopover(
                                    servers: editSlashCommand.servers,
                                    filterText: editSlashCommand.filterText,
                                    highlightedIndex: editSlashCommand.highlightedIndex,
                                    onSelectServer: editSlashCommand.onSelectServer,
                                    onDismiss: editSlashCommand.onDismiss
                                )
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .animation(.easeOut(duration: 0.12), value: editSlashCommand.isActive)
                            }

                            if !editSlashCommand.perMessageChips.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: JinSpacing.xSmall) {
                                        ForEach(editSlashCommand.perMessageChips) { chip in
                                            PerMessageMCPChip(
                                                name: chip.name,
                                                onRemove: { editSlashCommand.onRemovePerMessageServer(chip.id) }
                                            )
                                        }
                                    }
                                }
                            }

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
                                },
                                onInterceptKeyDown: editSlashCommand.onInterceptKeyDown
                            )
                            .frame(minHeight: 36, maxHeight: 400)
                        } else {
                            if isUser, !item.perMessageMCPServerNames.isEmpty {
                                UserMessageMCPBadgeRow(serverNames: item.perMessageMCPServerNames)
                            }

                            if !item.searchActivities.isEmpty {
                                SearchActivityTimelineView(
                                    activities: item.searchActivities,
                                    isStreaming: false,
                                    providerLabel: assistantDisplayName == "Assistant" ? nil : assistantDisplayName,
                                    modelLabel: assistantModelLabel
                                )
                            }

                            if !item.codexToolActivities.isEmpty {
                                CodexToolTimelineView(
                                    activities: item.codexToolActivities,
                                    isStreaming: false
                                )
                            }

                            if !item.agentToolActivities.isEmpty {
                                AgentToolTimelineView(
                                    activities: item.agentToolActivities,
                                    isStreaming: false
                                )
                            }

                            if !item.codeExecutionActivities.isEmpty {
                                CodeExecutionTimelineView(
                                    activities: item.codeExecutionActivities,
                                    isStreaming: false
                                )
                            }

                            if isUser {
                                userBlocksView(blocks: item.renderedBlocks)
                            } else {
                                ForEach(Array(item.renderedBlocks.enumerated()), id: \.offset) { _, block in
                                    switch block {
                                    case .content(let part):
                                        ContentPartView(
                                            part: part,
                                            isUser: false,
                                            deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
                                        )

                                    case .artifact(let artifact):
                                        MessageArtifactCardView(artifact: artifact) {
                                            onOpenArtifact(artifact, item.contextThreadID)
                                        }
                                    }
                                }
                            }

                            if !visibleToolCalls.isEmpty {
                                MCPToolTimelineView(
                                    toolCalls: visibleToolCalls,
                                    toolResultsByCallID: toolResultsByCallID,
                                    isStreaming: false
                                )
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
                            canEditUserMessage: canEditUserMessage,
                            canDeleteResponse: canDeleteResponse,
                            responseMetrics: item.responseMetrics
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
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate?()
        }
        .alert(
            pendingDeleteAction == .response ? "Delete response?" : "Delete message?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                switch pendingDeleteAction {
                case .message:
                    onDeleteMessage(item.id)
                case .response:
                    onDeleteResponse(item.id)
                case .none:
                    break
                }
                pendingDeleteAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAction = nil
            }
        }
    }

    @ViewBuilder
    private func headerView(isUser: Bool, isTool: Bool, assistantModelLabel: String?) -> some View {
        if isUser {
            EmptyView()
        } else {
            HStack(spacing: JinSpacing.small - 2) {
                if !isTool {
                    ProviderBadgeIcon(iconID: item.assistantProviderIconID ?? providerIconID)
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
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func footerView(
        isUser: Bool,
        isAssistant: Bool,
        isEditingUserMessage: Bool,
        showsCopyButton: Bool,
        copyText: String,
        canEditUserMessage: Bool,
        canDeleteResponse: Bool,
        responseMetrics: ResponseMetrics?
    ) -> some View {
        if isAssistant {
            HStack(spacing: JinSpacing.small) {
                if showsCopyButton {
                    CopyToPasteboardButton(text: copyText, helpText: "Copy message", useProminentStyle: false)
                        .accessibilityLabel("Copy message")
                }

                if let responseMetrics {
                    actionIconButton(systemName: "gauge", helpText: "Response metrics") {
                        isResponseMetricsPopoverPresented.toggle()
                    }
                    .popover(isPresented: $isResponseMetricsPopoverPresented, arrowEdge: .top) {
                        ResponseMetricsPopover(metrics: responseMetrics)
                    }
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
                    .disabled(copyText.isEmpty || !textToSpeechConfigured)

                    if textToSpeechIsActive {
                        actionIconButton(systemName: "stop.circle", helpText: textToSpeechStopHelpText) {
                            onStopSpeakAssistantMessage(item.id)
                        }
                    }
                }

                actionIconButton(systemName: "arrow.clockwise", helpText: "Regenerate") {
                    onRegenerate(item.id)
                }

                Menu {
                    Button(role: .destructive) {
                        pendingDeleteAction = .message
                        showingDeleteConfirmation = true
                    } label: {
                        deleteActionMenuLabel("Delete message", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .help("More actions")

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

                    actionIconButton(systemName: "paperplane", helpText: "Resend") {
                        onSubmitUserEdit(item.id)
                    }
                } else {
                    Spacer(minLength: 0)

                    if showsCopyButton {
                        CopyToPasteboardButton(text: copyText, helpText: "Copy message", useProminentStyle: false)
                            .accessibilityLabel("Copy message")
                    }

                    actionIconButton(systemName: "arrow.clockwise", helpText: "Regenerate") {
                        onRegenerate(item.id)
                    }

                    if canEditUserMessage {
                        actionIconButton(systemName: "pencil", helpText: "Edit") {
                            onEditUserMessage(item.id)
                        }
                    }

                    Menu {
                        Button(role: .destructive) {
                            pendingDeleteAction = .message
                            showingDeleteConfirmation = true
                        } label: {
                            deleteActionMenuLabel("Delete message", systemImage: "trash")
                        }

                        if canDeleteResponse {
                            Button(role: .destructive) {
                                pendingDeleteAction = .response
                                showingDeleteConfirmation = true
                            } label: {
                                deleteActionMenuLabel("Delete response", systemImage: "text.badge.minus")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: JinControlMetrics.iconButtonGlyphSize, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 20)
                    .help("More actions")
                }
            }
        }
    }

    @ViewBuilder
    private func userBlocksView(blocks: [RenderedMessageBlock]) -> some View {
        let imageBlocks = blocks.compactMap { block -> ContentPart? in
            if case .content(let part) = block, case .image = part { return part }
            return nil
        }
        let nonImageBlocks = blocks.filter { block in
            if case .content(let part) = block, case .image = part { return false }
            return true
        }

        if !imageBlocks.isEmpty {
            HStack(spacing: JinSpacing.small) {
                ForEach(Array(imageBlocks.enumerated()), id: \.offset) { _, part in
                    ContentPartView(part: part, isUser: true, deferCodeHighlightUpgrade: deferCodeHighlightUpgrade)
                }
            }
        }

        ForEach(Array(nonImageBlocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .content(let part):
                ContentPartView(part: part, isUser: true, deferCodeHighlightUpgrade: deferCodeHighlightUpgrade)
            case .artifact(let artifact):
                MessageArtifactCardView(artifact: artifact) {
                    onOpenArtifact(artifact, item.contextThreadID)
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

    private func deleteActionMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 14, alignment: .center)
        }
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
            return "Configure Text to Speech in Settings -> Plugins -> Text to Speech"
        }
        if textToSpeechIsGenerating {
            return "Generating speech..."
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

// MARK: - Provider Badge Icon

struct ProviderBadgeIcon: View {
    let iconID: String?

    var body: some View {
        ProviderIconView(iconID: iconID, fallbackSystemName: "network", size: 14)
            .frame(width: 14, height: 14)
    }
}
