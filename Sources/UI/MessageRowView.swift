import SwiftUI
import AppKit
import AVFoundation
import AVKit
import CryptoKit

// MARK: - Video Helpers

private func persistVideoToDisk(from url: URL) async -> URL? {
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let dir = appSupport.appendingPathComponent("Jin/Attachments", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    do {
        let (data, response) = try await URLSession.shared.data(from: url)

        let contentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        let ext = videoFileExtension(contentType: contentType, url: url)

        let filename = "\(UUID().uuidString).\(ext)"
        let destination = dir.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return destination
    } catch {
        return nil
    }
}

private func videoFileExtension(contentType: String?, url: URL) -> String {
    let mimeToExt: [String: String] = [
        "video/mp4": "mp4",
        "video/quicktime": "mov",
        "video/webm": "webm",
        "video/x-msvideo": "avi",
        "video/x-matroska": "mkv",
    ]

    if let ct = contentType, let ext = mimeToExt[ct] {
        return ext
    }

    let urlExt = url.pathExtension.lowercased()
    if !urlExt.isEmpty {
        return urlExt
    }

    return "mp4"
}

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
                if let localURL = await persistVideoToDisk(from: url) {
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

// MARK: - Render Models

struct MessageRenderItem: Identifiable {
    let id: UUID
    let contextThreadID: UUID?
    let role: String
    let timestamp: Date
    let renderedContentParts: [RenderedMessageContentPart]
    let toolCalls: [ToolCall]
    let searchActivities: [SearchActivity]
    let assistantModelLabel: String?
    let copyText: String
    let canEditUserMessage: Bool

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isTool: Bool { role == "tool" }
}

struct RenderedMessageContentPart {
    let part: ContentPart
}

// MARK: - Message Row

struct MessageRow: View {
    let item: MessageRenderItem
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let providerIconID: String?
    let deferCodeHighlightUpgrade: Bool
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
    let onActivate: (() -> Void)?

    var body: some View {
        let isUser = item.isUser
        let isAssistant = item.isAssistant
        let isTool = item.isTool
        let isEditingUserMessage = isUser && editingUserMessageID == item.id
        let assistantModelLabel = item.assistantModelLabel
        let copyText = item.copyText
        let showsCopyButton = (isUser || isAssistant) && !copyText.isEmpty
        let canEditUserMessage = item.canEditUserMessage
        let visibleToolCalls = item.toolCalls.filter { call in
            !BuiltinSearchToolHub.isBuiltinSearchFunctionName(call.name)
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
                            .frame(minHeight: 36, maxHeight: 400)
                        } else {
                            if !item.searchActivities.isEmpty {
                                SearchActivityTimelineView(
                                    activities: item.searchActivities,
                                    isStreaming: false,
                                    providerLabel: assistantDisplayName == "Assistant" ? nil : assistantDisplayName,
                                    modelLabel: assistantModelLabel
                                )
                            }

                            ForEach(Array(item.renderedContentParts.enumerated()), id: \.offset) { _, rendered in
                                ContentPartView(
                                    part: rendered.part,
                                    isUser: isUser,
                                    deferCodeHighlightUpgrade: deferCodeHighlightUpgrade
                                )
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
        .contentShape(Rectangle())
        .onTapGesture {
            onActivate?()
        }
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
            .padding(.bottom, 2)
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
                    Spacer(minLength: 0)

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
            } else if let url = image.url {
                Link(url.absoluteString, destination: url)
                    .font(.caption)
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
                }

                Button {
                    if let fileURL {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } else if let savedURL = Self.persistImageToDisk(data: imageData, image: image, mimeType: mimeType) {
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

    private static func persistImageToDisk(data: Data?, image: NSImage, mimeType: String) -> URL? {
        let imageData: Data
        if let data {
            imageData = data
        } else if let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            imageData = png
        } else {
            return nil
        }

        let ext = AttachmentStorageManager.fileExtension(for: mimeType) ?? "png"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir = appSupport?.appendingPathComponent("Jin/Attachments", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let hash = SHA256.hash(data: imageData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let url = dir.appendingPathComponent("\(hashString).\(ext)")

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        do {
            try imageData.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
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
