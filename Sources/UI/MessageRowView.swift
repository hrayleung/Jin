import SwiftUI
import AppKit
import AVFoundation
import AVKit
import Foundation
import Kingfisher

// MARK: - JinAVPlayerView (AppKit subclass with context menu)

/// Custom AVPlayerView that provides a native context menu with Reveal in Finder,
/// since SwiftUI `.contextMenu` does not receive right-click events from NSViewRepresentable.
private final class JinAVPlayerView: AVPlayerView {
    var mediaURL: URL?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url = mediaURL else { return nil }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open", action: #selector(openMedia), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        menu.addItem(openItem)

        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        revealItem.target = self
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(revealItem)

        menu.addItem(.separator())

        if url.isFileURL {
            let copyItem = NSMenuItem(title: "Copy Path", action: #selector(copyPathOrURL), keyEquivalent: "")
            copyItem.target = self
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyItem)
        } else {
            let copyItem = NSMenuItem(title: "Copy URL", action: #selector(copyPathOrURL), keyEquivalent: "")
            copyItem.target = self
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            menu.addItem(copyItem)
        }

        return menu
    }

    @objc private func openMedia() {
        guard let url = mediaURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealInFinder() {
        guard let url = mediaURL else { return }
        if url.isFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            Task {
                if let localURL = await MessageMediaAssetPersistenceSupport.persistRemoteVideoToDisk(from: url) {
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([localURL])
                    }
                }
            }
        }
    }

    @objc private func copyPathOrURL() {
        guard let url = mediaURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
    }
}

// MARK: - VideoPlayerView (NSViewRepresentable)

/// Wraps JinAVPlayerView to provide video playback with a native context menu.
private struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> JinAVPlayerView {
        let view = JinAVPlayerView()
        view.player = AVPlayer(url: url)
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.mediaURL = url
        return view
    }

    func updateNSView(_ nsView: JinAVPlayerView, context: Context) {
        if (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            nsView.player = AVPlayer(url: url)
            nsView.mediaURL = url
        }
    }
}

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

private struct ResponseMetricsPopover: View {
    let metrics: ResponseMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            metricRow(title: "Input tokens", value: formattedTokens(metrics.usage?.inputTokens))
            metricRow(title: "Output tokens", value: formattedTokens(metrics.usage?.outputTokens))
            metricRow(title: "Time to first token", value: formattedSeconds(metrics.timeToFirstTokenSeconds))
            metricRow(title: "Duration", value: formattedSeconds(metrics.durationSeconds))
            metricRow(title: "Output speed", value: formattedSpeed(metrics.outputTokensPerSecond))
        }
        .padding(.vertical, JinSpacing.small)
        .padding(.horizontal, JinSpacing.medium)
        .frame(minWidth: 260, alignment: .leading)
    }

    @ViewBuilder
    private func metricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JinSpacing.large) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(.callout)
    }

    private func formattedTokens(_ value: Int?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.grouping(.automatic))
    }

    private func formattedSeconds(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1fs", value)
    }

    private func formattedSpeed(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1fT/s", value)
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

struct ArtifactTypeBadge: View {
    let contentType: ArtifactContentType

    var body: some View {
        Text(contentType.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(JinSemanticColor.subtleSurface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(JinSemanticColor.separator.opacity(0.45), lineWidth: JinStrokeWidth.hairline)
            )
    }
}

struct MessageArtifactCardView: View {
    let artifact: RenderedArtifactVersion
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: JinSpacing.small) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(artifactAccentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: artifactIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(artifactAccentColor)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        ArtifactTypeBadge(contentType: artifact.contentType)

                        Text("Artifact")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Text("Open")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(artifactAccentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(artifactAccentColor.opacity(isHovered ? 0.18 : 0.1))
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 400, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .fill(JinSemanticColor.subtleSurface.opacity(isHovered ? 1 : 0.7))
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: JinRadius.small,
                    bottomLeadingRadius: JinRadius.small,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(artifactAccentColor)
                .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(
                        artifactAccentColor.opacity(isHovered ? 0.25 : 0.1),
                        lineWidth: JinStrokeWidth.hairline
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Open \(artifact.title)")
    }

    private var artifactAccentColor: Color {
        switch artifact.contentType {
        case .react:
            return Color(red: 0.55, green: 0.68, blue: 0.78)
        case .html:
            return Color(red: 0.75, green: 0.58, blue: 0.50)
        case .echarts:
            return Color(red: 0.55, green: 0.70, blue: 0.60)
        }
    }

    private var artifactIconName: String {
        switch artifact.contentType {
        case .react:
            return "atom"
        case .html:
            return "globe"
        case .echarts:
            return "chart.bar.xaxis"
        }
    }
}

// MARK: - Content Part View

struct ContentPartView: View {
    let part: ContentPart
    var isUser: Bool = false
    var deferCodeHighlightUpgrade: Bool = false

    var body: some View {
        switch part {
        case .text(let text):
            MessageTextView(
                text: text,
                mode: isUser ? .plainText : .markdown,
                deferCodeHighlightUpgrade: (!isUser && deferCodeHighlightUpgrade)
            )

        case .thinking(let thinking):
            ThinkingBlockView(thinking: thinking)

        case .redactedThinking:
            EmptyView()

        case .image(let image):
            let fileURL = (image.url?.isFileURL == true) ? image.url : nil

            if let data = image.data, let nsImage = NSImage(data: data) {
                renderedImage(nsImage, fileURL: fileURL, imageData: data, mimeType: image.mimeType)
            } else if let fileURL, let nsImage = NSImage(contentsOf: fileURL) {
                renderedImage(nsImage, fileURL: fileURL, imageData: nil, mimeType: image.mimeType)
            } else if let url = image.remoteURL {
                RemoteMessageImageView(image: image, url: url, isUser: isUser)
            }

        case .video(let video):
            renderedVideo(video)

        case .file(let file):
            fileContentView(file)

        case .audio:
            Label("Audio content", systemImage: "waveform")
                .padding(JinSpacing.small)
                .jinSurface(.neutral, cornerRadius: JinRadius.small)
        }
    }

    @ViewBuilder
    private func fileContentView(_ file: FileContent) -> some View {
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
                fileContextMenu(url: url, filename: file.filename, extractedText: file.extractedText)
            }
        } else {
            row
                .contextMenu {
                    filenameOnlyContextMenu(filename: file.filename, extractedText: file.extractedText)
                }
        }
    }

    @ViewBuilder
    private func fileContextMenu(url: URL, filename: String, extractedText: String?) -> some View {
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
            pasteboard.setString(filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(extractedText)
    }

    @ViewBuilder
    private func filenameOnlyContextMenu(filename: String, extractedText: String?) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(filename, forType: .string)
        } label: {
            Label("Copy Filename", systemImage: "doc.on.doc")
        }

        extractedTextCopyButton(extractedText)
    }

    @ViewBuilder
    private func extractedTextCopyButton(_ extractedText: String?) -> some View {
        if let extracted = extractedText?.trimmingCharacters(in: .whitespacesAndNewlines), !extracted.isEmpty {
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

    @ViewBuilder
    private func renderedVideo(_ video: VideoContent) -> some View {
        if let fileURL = video.url, fileURL.isFileURL {
            VideoPlayerView(url: fileURL)
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
        } else if let url = video.url {
            VideoPlayerView(url: url)
                .frame(maxWidth: 560, minHeight: 220, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
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
    private func renderedImage(_ image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        if isUser {
            userImageThumbnail(image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
        } else {
            fullSizeImage(image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
        }
    }

    @ViewBuilder
    private func userImageThumbnail(_ image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: JinStrokeWidth.hairline)
            )
            .onTapGesture {
                if let fileURL {
                    NSWorkspace.shared.open(fileURL)
                } else if let savedURL = MessageMediaAssetPersistenceSupport.persistImageToDisk(
                    data: imageData,
                    image: image,
                    mimeType: mimeType
                ) {
                    NSWorkspace.shared.open(savedURL)
                }
            }
            .onDrag {
                if let fileURL {
                    return NSItemProvider(contentsOf: fileURL) ?? NSItemProvider(object: fileURL as NSURL)
                }
                return NSItemProvider(object: image)
            }
            .contextMenu {
                imageContextMenu(image: image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
            }
    }

    @ViewBuilder
    private func fullSizeImage(_ image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
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
                imageContextMenu(image: image, fileURL: fileURL, imageData: imageData, mimeType: mimeType)
            }
    }

    @ViewBuilder
    private func imageContextMenu(image: NSImage, fileURL: URL?, imageData: Data?, mimeType: String) -> some View {
        if let fileURL {
            Button {
                NSWorkspace.shared.open(fileURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
        }

        Button {
            if let fileURL {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } else if let savedURL = MessageMediaAssetPersistenceSupport.persistImageToDisk(
                data: imageData,
                image: image,
                mimeType: mimeType
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
            }
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }

        Divider()

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

private struct RemoteMessageImageView: View {
    let image: ImageContent
    let url: URL
    var isUser: Bool = false

    @State private var loadFailed = false

    var body: some View {
        Group {
            if loadFailed {
                fallbackView
            } else if isUser {
                KFImage(source: .network(KF.ImageResource(downloadURL: url)))
                    .placeholder { _ in userPlaceholderView }
                    .cancelOnDisappear(true)
                    .fade(duration: 0.15)
                    .onSuccess { _ in loadFailed = false }
                    .onFailure { _ in loadFailed = true }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: JinStrokeWidth.hairline)
                    )
                    .onTapGesture {
                        NSWorkspace.shared.open(url)
                    }
            } else {
                KFImage(source: .network(KF.ImageResource(downloadURL: url)))
                    .placeholder { _ in placeholderView }
                    .cancelOnDisappear(true)
                    .fade(duration: 0.15)
                    .onSuccess { _ in loadFailed = false }
                    .onFailure { _ in loadFailed = true }
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 500)
                    .clipShape(RoundedRectangle(cornerRadius: JinRadius.small, style: .continuous))
            }
        }
        .task(id: url) {
            loadFailed = false
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.absoluteString, forType: .string)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            if image.assetDisposition == .externalReference {
                Divider()

                Text("External reference")
            }
        }
    }

    private var userPlaceholderView: some View {
        ProgressView()
            .controlSize(.small)
            .frame(width: 80, height: 80)
            .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }

    private var placeholderView: some View {
        VStack(spacing: JinSpacing.small) {
            ProgressView()
                .controlSize(.small)
            Text("Loading image…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 500, minHeight: 120)
        .padding(JinSpacing.medium)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }

    private var fallbackView: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Unable to load image preview", systemImage: "photo")
                .font(.callout.weight(.medium))
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .frame(maxWidth: 500, alignment: .leading)
        .padding(JinSpacing.medium)
        .jinSurface(.neutral, cornerRadius: JinRadius.small)
    }
}

// MARK: - Chunked Text View

struct ChunkedTextView: View {
    let chunks: [String]
    let font: Font
    let allowsTextSelection: Bool

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            ForEach(chunks.indices, id: \.self) { idx in
                Text(verbatim: chunks[idx])
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if allowsTextSelection {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

// MARK: - Load Earlier Messages

struct LoadEarlierMessagesRow: View {
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
