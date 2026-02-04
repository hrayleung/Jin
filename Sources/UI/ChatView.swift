import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PDFKit

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversationEntity: ConversationEntity
    let onRequestDeleteConversation: () -> Void
    @Binding var isAssistantInspectorPresented: Bool
    @Query private var providers: [ProviderConfigEntity]
    @Query private var mcpServers: [MCPServerConfigEntity]

    @State private var controls: GenerationControls = GenerationControls()
    @State private var messageText = ""
    @State private var draftAttachments: [DraftAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var isComposerDropTargeted = false
    @State private var isComposerFocused = false
    @State private var isStreaming = false
    @State private var streamingMessage: StreamingMessageState?
    @State private var streamingTask: Task<Void, Never>?
    @State private var rerunToolResultsByCallID: [String: ToolResult] = [:]
    @State private var rerunningToolCallIDs: Set<String> = []

    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingThinkingBudgetSheet = false
    @State private var thinkingBudgetDraft = ""
    @State private var maxTokensDraft = ""

    @State private var showingProviderSpecificParamsSheet = false
    @State private var providerSpecificParamsDraft = ""
    @State private var providerSpecificParamsError: String?

    private var orderedMessages: [MessageEntity] {
        conversationEntity.messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        let bubbleMaxWidth = maxBubbleWidth(for: geometry.size.width)
                        let assistantDisplayName = conversationEntity.assistant?.displayName ?? "Assistant"
                        let assistantIcon = conversationEntity.assistant?.icon
                        let toolResultsByCallID = toolResultsByToolCallID(in: orderedMessages)
                            .merging(rerunToolResultsByCallID) { _, new in new }
                        let visibleMessages = orderedMessages.filter { $0.role != "tool" }
                        LazyVStack(alignment: .leading, spacing: 0) { // Zero spacing, controlled by padding in rows
                            ForEach(visibleMessages) { message in
                                MessageRow(
                                    messageEntity: message,
                                    maxBubbleWidth: bubbleMaxWidth,
                                    assistantDisplayName: assistantDisplayName,
                                    assistantIcon: assistantIcon,
                                    toolResultsByCallID: toolResultsByCallID,
                                    isRerunAllowed: !isStreaming,
                                    isToolCallRerunning: { toolCallID in
                                        rerunningToolCallIDs.contains(toolCallID)
                                    },
                                    onRerunToolCall: { toolCall in
                                        rerunToolCall(toolCall)
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
                                    assistantIcon: assistantIcon
                                )
                                    .id("streaming")
                            }
                            
                            Spacer(minLength: 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical)
                    }
                    .onChange(of: conversationEntity.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: streamingMessage) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            Divider()

            // Desktop-class Composer
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !draftAttachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(draftAttachments) { attachment in
                                        DraftAttachmentChip(
                                            attachment: attachment,
                                            onRemove: { removeDraftAttachment(attachment) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            if messageText.isEmpty {
                                Text("Type a message...")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
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
                                .frame(minHeight: 40, maxHeight: 160)
                        }

                        Divider()
                            .padding(.horizontal, 2)

                        HStack(spacing: 6) {
                            Button {
                                isFileImporterPresented = true
                            } label: {
                                controlIconLabel(
                                    systemName: "paperclip",
                                    isActive: !draftAttachments.isEmpty,
                                    badgeText: draftAttachments.isEmpty ? nil : "\(draftAttachments.count)"
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Attach images / PDFs")
                            .disabled(isStreaming)

                            Menu {
                                reasoningMenuContent
                            } label: {
                                controlIconLabel(
                                    systemName: "brain",
                                    isActive: isReasoningEnabled,
                                    badgeText: reasoningBadgeText
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(!supportsReasoningControl)
                            .help(reasoningHelpText)

                            Menu {
                                webSearchMenuContent
                            } label: {
                                controlIconLabel(
                                    systemName: "globe",
                                    isActive: isWebSearchEnabled,
                                    badgeText: webSearchBadgeText
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(!supportsWebSearchControl)
                            .help(webSearchHelpText)

                            Menu {
                                mcpToolsMenuContent
                            } label: {
                                controlIconLabel(
                                    systemName: "hammer",
                                    isActive: supportsMCPToolsControl && isMCPToolsEnabled,
                                    badgeText: mcpToolsBadgeText
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .disabled(!supportsMCPToolsControl)
                            .help(mcpToolsHelpText)

                            Menu {
                                providerSpecificParamsMenuContent
                            } label: {
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
                        .padding(.bottom, 2)
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isComposerDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                    Button(action: sendMessage) {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(isStreaming ? .red : (canSendDraft ? Color.accentColor : .gray))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendDraft && !isStreaming)
                    .padding(.bottom, 4)
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor)) // Main chat background
        .navigationTitle(conversationEntity.title)
        .navigationSubtitle(currentModelName)
        .toolbar {
            ToolbarItemGroup {
                modelPickerMenu

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAssistantInspectorPresented.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
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
                        Text("Use token budgets to control extended thinking and tool interleaving.")
                            .foregroundStyle(.secondary)

                        TextField("Thinking budget tokens", text: $thinkingBudgetDraft)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        TextField("Max tokens (optional)", text: $maxTokensDraft)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        if let warning = thinkingBudgetValidationWarning {
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                        .disabled(thinkingBudgetDraftInt == nil)
                    }
                }
            }
            .frame(width: 420)
        }
        .sheet(isPresented: $showingProviderSpecificParamsSheet) {
            NavigationStack {
                Form {
                    Section("Provider-specific parameters (JSON)") {
                        TextEditor(text: $providerSpecificParamsDraft)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 220)
                            .onChange(of: providerSpecificParamsDraft) { _, _ in
                                providerSpecificParamsError = nil
                            }

                        if let providerSpecificParamsError {
                            Text(providerSpecificParamsError)
                                .foregroundStyle(.red)
                                .font(.caption)
                        } else {
                            Text("These fields are merged into the provider request body (overrides take precedence).")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section("Examples") {
                        Text("Fireworks GLM/Kimi thinking history: {\"reasoning_history\": \"preserved\"} (or \"interleaved\" / \"turn_level\")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Cerebras GLM preserved thinking: {\"clear_thinking\": false}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Cerebras GLM disable thinking: {\"disable_reasoning\": true}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Cerebras reasoning output: {\"reasoning_format\": \"parsed\"} (or \"raw\" / \"hidden\" / \"none\")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Provider Params")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
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
        .task {
            loadControlsFromConversation()
        }
        .focusedSceneValue(
            \.chatActions,
            ChatFocusedActions(
                canAttach: !isStreaming,
                canStopStreaming: isStreaming,
                focusComposer: { isComposerFocused = true },
                attach: { isFileImporterPresented = true },
                stopStreaming: {
                    guard isStreaming else { return }
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

    private func removeDraftAttachment(_ attachment: DraftAttachment) {
        draftAttachments.removeAll { $0.id == attachment.id }
        try? FileManager.default.removeItem(at: attachment.fileURL)
    }

    private func handleDroppedFileURLs(_ urls: [URL]) -> Bool {
        let uniqueURLs = Array(Set(urls))
        guard !uniqueURLs.isEmpty else { return false }

        if isStreaming {
            errorMessage = "Stop generating to attach files."
            showingError = true
            return true
        }

        Task { await importAttachments(from: uniqueURLs) }
        return true
    }

    private func handleDroppedImages(_ images: [NSImage]) -> Bool {
        guard !images.isEmpty else { return false }

        if isStreaming {
            errorMessage = "Stop generating to attach files."
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
        guard !isStreaming else { return }
        sendMessage()
    }

    private func handleComposerCancel() -> Bool {
        guard isStreaming else { return false }
        sendMessage()
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        if isStreaming {
            errorMessage = "Stop generating to attach files."
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
                let extractedText = extractTextFromPDF(at: entity.fileURL)
                return .success(
                    DraftAttachment(
                        id: entity.id,
                        filename: entity.filename,
                        mimeType: entity.mimeType,
                        fileURL: entity.fileURL,
                        extractedText: extractedText
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

    private static func extractTextFromPDF(at url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }

        var pieces: [String] = []
        pieces.reserveCapacity(min(16, document.pageCount))

        for index in 0..<document.pageCount {
            if let pageText = document.page(at: index)?.string, !pageText.isEmpty {
                pieces.append(pageText)
            }
        }

        let combined = pieces.joined(separator: "\n\n")
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count > AttachmentConstants.maxPDFExtractedCharacters {
            let prefix = trimmed.prefix(AttachmentConstants.maxPDFExtractedCharacters)
            return "\(prefix)\n\n[Truncated]"
        }

        return trimmed
    }

    private struct DraftAttachmentChip: View {
        let attachment: DraftAttachment
        let onRemove: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Group {
                    if attachment.isImage, let image = NSImage(contentsOf: attachment.fileURL) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
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

    private var selectedReasoningConfig: ModelReasoningConfig? {
        selectedModelInfo?.reasoningConfig
    }

    private var isReasoningEnabled: Bool {
        controls.reasoning?.enabled == true
    }

    private var isWebSearchEnabled: Bool {
        controls.webSearch?.enabled == true
    }

    private var isMCPToolsEnabled: Bool {
        controls.mcpTools?.enabled ?? true
    }

    private var supportsReasoningControl: Bool {
        guard let config = selectedReasoningConfig else { return false }
        return config.type != .none
    }

    private var supportsWebSearchControl: Bool {
        // Provider-native web search, not MCP. Today: OpenAI, Anthropic, xAI, Vertex AI.
        switch providerType {
        case .openai, .anthropic, .xai, .vertexai:
            return true
        case .fireworks, .cerebras, .none:
            return false
        }
    }

    private var supportsMCPToolsControl: Bool {
        selectedModelInfo?.capabilities.contains(.toolCalling) == true
    }

    private var reasoningHelpText: String {
        guard supportsReasoningControl else { return "Reasoning: Not supported" }
        switch providerType {
        case .anthropic, .vertexai:
            return "Thinking: \(reasoningLabel)"
        case .openai, .xai, .fireworks, .cerebras, .none:
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
        case .xai:
            return webSearchSourcesLabel
        case .anthropic, .vertexai, .fireworks, .cerebras, .none:
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
        case .xai:
            let sources = Set(controls.webSearch?.sources ?? [])
            if sources == [.web] { return "W" }
            if sources == [.x] { return "X" }
            if sources.contains(.web), sources.contains(.x) { return "W+X" }
            return "On"
        case .anthropic, .vertexai, .fireworks, .cerebras, .none:
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

    @ViewBuilder
    private func controlIconLabel(systemName: String, isActive: Bool, badgeText: String?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                )

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .offset(x: 4, y: 4)
            }
        }
    }

    private var modelPickerMenu: some View {
        Menu {
            Section("Provider") {
                ForEach(providers) { provider in
                    Button {
                        setProvider(provider.id)
                    } label: {
                        HStack {
                            Text(provider.name)
                            if provider.id == conversationEntity.providerID {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Model") {
                if availableModels.isEmpty {
                    Text("No models configured.")
                } else {
                    ForEach(availableModels) { model in
                        Button {
                            setModel(model.id)
                        } label: {
                            HStack {
                                Text(model.name)
                                if isFullySupportedModel(modelID: model.id) {
                                    Text("Full")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .foregroundStyle(.green)
                                        .background(
                                            Capsule()
                                                .fill(Color.green.opacity(0.12))
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.green.opacity(0.35), lineWidth: 0.5)
                                        )
                                }
                                if model.id == conversationEntity.modelID {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentModelName)
                    .font(.callout)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentModelName: String {
        availableModels.first(where: { $0.id == conversationEntity.modelID })?.name ?? conversationEntity.modelID
    }

    private var availableModels: [ModelInfo] {
        guard let provider = providers.first(where: { $0.id == conversationEntity.providerID }),
              let models = try? JSONDecoder().decode([ModelInfo].self, from: provider.modelsData) else {
            return []
        }
        return models
    }

    private func isFullySupportedModel(modelID: String) -> Bool {
        guard let providerType else { return false }
        let lower = modelID.lowercased()

        switch providerType {
        case .fireworks:
            return lower == "fireworks/kimi-k2p5"
                || lower == "accounts/fireworks/models/kimi-k2p5"
                || lower == "fireworks/glm-4p7"
                || lower == "accounts/fireworks/models/glm-4p7"
        case .cerebras:
            return lower == "zai-glm-4.7"
        case .openai, .anthropic, .xai, .vertexai:
            return false
        }
    }

    private func setProvider(_ providerID: String) {
        guard providerID != conversationEntity.providerID else { return }

        conversationEntity.providerID = providerID
        conversationEntity.updatedAt = Date()

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
        conversationEntity.updatedAt = Date()
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
            return models.first(where: { $0.id == "claude-sonnet-4-5-20250929" })?.id
        case .fireworks:
            return models.first(where: { $0.id.lowercased() == "fireworks/kimi-k2p5" || $0.id.lowercased() == "accounts/fireworks/models/kimi-k2p5" })?.id
                ?? models.first(where: { $0.id.lowercased() == "fireworks/glm-4p7" || $0.id.lowercased() == "accounts/fireworks/models/glm-4p7" })?.id
        case .cerebras:
            return models.first(where: { $0.id == "zai-glm-4.7" })?.id
        case .xai, .vertexai:
            return nil
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = orderedMessages.last(where: { $0.role != "tool" }) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        } else if streamingMessage != nil {
            proxy.scrollTo("streaming", anchor: .bottom)
        }
    }

    private func toolResultsByToolCallID(in messageEntities: [MessageEntity]) -> [String: ToolResult] {
        var results: [String: ToolResult] = [:]
        results.reserveCapacity(8)

        for entity in messageEntities where entity.role == "tool" {
            guard let message = try? entity.toDomain() else { continue }
            for result in message.toolResults ?? [] {
                results[result.toolCallID] = result
            }
        }

        return results
    }

    private func rerunToolCall(_ toolCall: ToolCall) {
        guard !isStreaming else { return }
        guard !rerunningToolCallIDs.contains(toolCall.id) else { return }

        rerunningToolCallIDs.insert(toolCall.id)

        Task {
            let callStart = Date()
            do {
                let servers = resolvedMCPServerConfigs(for: controls)
                guard !servers.isEmpty else {
                    throw LLMError.invalidRequest(message: "No MCP servers are enabled for automatic tool use.")
                }

                _ = try await MCPHub.shared.toolDefinitions(for: servers)
                let result = try await MCPHub.shared.executeTool(functionName: toolCall.name, arguments: toolCall.arguments)
                let duration = Date().timeIntervalSince(callStart)
                let toolResult = ToolResult(
                    toolCallID: toolCall.id,
                    toolName: toolCall.name,
                    content: result.text,
                    isError: result.isError,
                    signature: toolCall.signature,
                    durationSeconds: duration
                )

                await MainActor.run {
                    rerunToolResultsByCallID[toolCall.id] = toolResult
                    rerunningToolCallIDs.remove(toolCall.id)
                }
            } catch {
                let duration = Date().timeIntervalSince(callStart)
                let toolResult = ToolResult(
                    toolCallID: toolCall.id,
                    toolName: toolCall.name,
                    content: error.localizedDescription,
                    isError: true,
                    signature: toolCall.signature,
                    durationSeconds: duration
                )

                await MainActor.run {
                    rerunToolResultsByCallID[toolCall.id] = toolResult
                    rerunningToolCallIDs.remove(toolCall.id)
                }
            }
        }
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

    private func truncatedHistory(_ history: [Message], contextWindow: Int, reservedOutputTokens: Int) -> [Message] {
        guard contextWindow > 0 else { return history }

        let effectiveReserved = min(max(0, reservedOutputTokens), contextWindow)
        let budget = max(0, contextWindow - effectiveReserved)

        guard history.count > 2 else { return history }

        var prefix: [Message] = []
        var index = 0
        while index < history.count, history[index].role == .system {
            prefix.append(history[index])
            index += 1
        }

        var totalTokens = prefix.reduce(0) { $0 + approximateTokenCount(for: $1) }
        var tail: [Message] = []

        for message in history[index...].reversed() {
            let tokens = approximateTokenCount(for: message)
            if totalTokens + tokens <= budget || tail.isEmpty {
                tail.append(message)
                totalTokens += tokens
                continue
            }
            break
        }

        return prefix + tail.reversed()
    }

    private func approximateTokenCount(for message: Message) -> Int {
        var tokens = 4 // role/metadata overhead

        for part in message.content {
            tokens += approximateTokenCount(for: part)
        }

        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                tokens += approximateTokenCount(for: call.name)
                for (key, value) in call.arguments {
                    tokens += approximateTokenCount(for: key)
                    tokens += approximateTokenCount(for: String(describing: value.value))
                }
                if let signature = call.signature {
                    tokens += approximateTokenCount(for: signature)
                }
            }
        }

        if let toolResults = message.toolResults {
            for result in toolResults {
                if let toolName = result.toolName {
                    tokens += approximateTokenCount(for: toolName)
                }
                tokens += approximateTokenCount(for: result.content)
                if let signature = result.signature {
                    tokens += approximateTokenCount(for: signature)
                }
            }
        }

        return tokens
    }

    private func approximateTokenCount(for part: ContentPart) -> Int {
        switch part {
        case .text(let text):
            return approximateTokenCount(for: text)
        case .thinking(let thinking):
            return approximateTokenCount(for: thinking.text)
        case .redactedThinking:
            return 16
        case .image(let image):
            if image.data != nil { return 1024 }
            if image.url != nil { return 256 }
            return 256
        case .file(let file):
            let extractedTokens = approximateTokenCount(for: file.extractedText ?? "")
            return approximateTokenCount(for: file.filename) + max(256, extractedTokens)
        case .audio:
            return 1024
        }
    }

    private func approximateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, trimmed.count / 4)
    }

    private func sendMessage() {
        if isStreaming {
            streamingTask?.cancel()
            return
        }

        guard canSendDraft else { return }

        var parts: [ContentPart] = []
        for attachment in draftAttachments {
            if attachment.isImage {
                parts.append(.image(ImageContent(mimeType: attachment.mimeType, data: nil, url: attachment.fileURL)))
            } else {
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
        }
        if !trimmedMessageText.isEmpty {
            parts.append(.text(trimmedMessageText))
        }

        let message = Message(
            role: .user,
            content: parts
        )

        do {
            let messageEntity = try MessageEntity.fromDomain(message)
            messageEntity.conversation = conversationEntity
            conversationEntity.messages.append(messageEntity)
            if conversationEntity.title == "New Chat" {
                if !trimmedMessageText.isEmpty {
                    conversationEntity.title = makeConversationTitle(from: trimmedMessageText)
                } else if let firstAttachment = draftAttachments.first {
                    conversationEntity.title = makeConversationTitle(from: (firstAttachment.filename as NSString).deletingPathExtension)
                }
            }
            conversationEntity.updatedAt = Date()
            messageText = ""
            draftAttachments = []
        } catch {
            print("Failed to create message: \(error)")
        }

        startStreamingResponse()
    }

    private func makeConversationTitle(from userText: String) -> String {
        let firstLine = userText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Chat" }
        return String(trimmed.prefix(48))
    }

    private func startStreamingResponse() {
        guard streamingTask == nil else { return }

        let streamingState = StreamingMessageState()
        streamingMessage = streamingState
        isStreaming = true

        let providerConfig = providers.first(where: { $0.id == conversationEntity.providerID }).flatMap { try? $0.toDomain() }
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
        if let assistant {
            controlsToUse.temperature = assistant.temperature
            if let maxOutputTokens = assistant.maxOutputTokens {
                controlsToUse.maxTokens = maxOutputTokens
            }
        }

        let shouldTruncateMessages = assistant?.truncateMessages ?? false
        let modelContextWindow = selectedModelInfo?.contextWindow ?? 128000
        let reservedOutputTokens = max(0, controlsToUse.maxTokens ?? 2048)
        let mcpServerConfigs = resolvedMCPServerConfigs(for: controlsToUse)
        let modelID = conversationEntity.modelID

        streamingTask = Task {
            do {
                guard let providerConfig else {
                    throw LLMError.invalidRequest(message: "Provider not found. Configure it in Settings.")
                }

                var history = baseHistory
                if let systemPrompt, !systemPrompt.isEmpty {
                    history.insert(Message(role: .system, content: [.text(systemPrompt)]), at: 0)
                }
                if shouldTruncateMessages {
                    history = truncatedHistory(
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

                    var assistantParts: [ContentPart] = []
                    var assistantText = ""
                    var assistantThinkingText = ""
                    var toolCallsByID: [String: ToolCall] = [:]

                    await MainActor.run {
                        streamingState.textContent = ""
                        streamingState.thinkingContent = ""
                    }

                    let stream = try await adapter.sendMessage(
                        messages: history,
                        modelID: modelID,
                        controls: controlsToUse,
                        tools: mcpTools,
                        streaming: true
                    )

                    for try await event in stream {
                        try Task.checkCancellation()

                        switch event {
                        case .messageStart: break
                        case .contentDelta(let part):
                            if case .text(let delta) = part {
                                assistantText += delta
                                appendTextDelta(delta, to: &assistantParts)
                                await MainActor.run { streamingState.textContent = assistantText }
                            }
                        case .thinkingDelta(let delta):
                            appendThinkingDelta(delta, to: &assistantParts)
                            switch delta {
                            case .thinking(let textDelta, _):
                                if !textDelta.isEmpty { assistantThinkingText += textDelta }
                            case .redacted:
                                assistantThinkingText = assistantThinkingText.isEmpty ? "Thinking (redacted)" : assistantThinkingText
                            }
                            await MainActor.run { streamingState.thinkingContent = assistantThinkingText }
                        case .toolCallStart(let call): toolCallsByID[call.id] = call
                        case .toolCallDelta: break
                        case .toolCallEnd(let call): toolCallsByID[call.id] = call
                        case .messageEnd: break
                        case .error(let err): throw err
                        }
                    }

                    let toolCalls = Array(toolCallsByID.values)
                    await MainActor.run {
                        if !assistantParts.isEmpty || !toolCalls.isEmpty {
                            let assistantMessage = Message(role: .assistant, content: assistantParts, toolCalls: toolCalls.isEmpty ? nil : toolCalls)
                            do {
                                let entity = try MessageEntity.fromDomain(assistantMessage)
                                entity.conversation = conversationEntity
                                conversationEntity.messages.append(entity)
                                conversationEntity.updatedAt = Date()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                            history.append(assistantMessage)
                        }
                    }

                    guard !toolCalls.isEmpty else { break }

                    await MainActor.run {
                        streamingState.textContent = "Running tools…"
                        streamingState.thinkingContent = ""
                    }

                    var toolResults: [ToolResult] = []
                    var toolOutputLines: [String] = []

                    for call in toolCalls {
                        let callStart = Date()
                        do {
                            let result = try await MCPHub.shared.executeTool(functionName: call.name, arguments: call.arguments)
                            let duration = Date().timeIntervalSince(callStart)
                            toolResults.append(
                                ToolResult(
                                    toolCallID: call.id,
                                    toolName: call.name,
                                    content: result.text,
                                    isError: result.isError,
                                    signature: call.signature,
                                    durationSeconds: duration
                                )
                            )
                            toolOutputLines.append("Tool \(call.name):\n\(result.text)")
                        } catch {
                            let duration = Date().timeIntervalSince(callStart)
                            toolResults.append(
                                ToolResult(
                                    toolCallID: call.id,
                                    toolName: call.name,
                                    content: error.localizedDescription,
                                    isError: true,
                                    signature: call.signature,
                                    durationSeconds: duration
                                )
                            )
                            toolOutputLines.append("Tool \(call.name) failed:\n\(error.localizedDescription)")
                        }
                    }

                    let toolMessage = Message(role: .tool, content: toolOutputLines.isEmpty ? [] : [.text(toolOutputLines.joined(separator: "\n\n"))], toolResults: toolResults)
                    await MainActor.run {
                        do {
                            let entity = try MessageEntity.fromDomain(toolMessage)
                            entity.conversation = conversationEntity
                            conversationEntity.messages.append(entity)
                            conversationEntity.updatedAt = Date()
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
                isStreaming = false
                streamingMessage = nil
                streamingTask = nil
            }
        }
    }

    private func appendTextDelta(_ delta: String, to parts: inout [ContentPart]) {
        if case .text(let existing) = parts.last {
            parts[parts.count - 1] = .text(existing + delta)
        } else {
            parts.append(.text(delta))
        }
    }

    private func appendThinkingDelta(_ delta: ThinkingDelta, to parts: inout [ContentPart]) {
        switch delta {
        case .thinking(let textDelta, let signature):
            // Anthropic signatures can arrive after (or alongside) the thinking text, and may stream
            // incrementally. Treat signature-only deltas as updates to the current thinking block.
            if textDelta.isEmpty, let signature, case .thinking(let existing) = parts.last {
                if existing.signature != signature {
                    parts[parts.count - 1] = .thinking(ThinkingBlock(text: existing.text, signature: signature))
                }
                return
            }
            if case .thinking(let existing) = parts.last, existing.signature == signature {
                if !textDelta.isEmpty {
                    parts[parts.count - 1] = .thinking(ThinkingBlock(text: existing.text + textDelta, signature: existing.signature))
                }
            } else {
                parts.append(.thinking(ThinkingBlock(text: textDelta, signature: signature)))
            }
        case .redacted(let data):
            parts.append(.redactedThinking(RedactedThinkingBlock(data: data)))
        }
    }
    
    // MARK: - Model Controls (Shortened for brevity, preserving existing logic)
    
    private var providerType: ProviderType? {
        guard let provider = providers.first(where: { $0.id == conversationEntity.providerID }) else { return nil }
        return ProviderType(rawValue: provider.typeRaw)
    }

    private var reasoningLabel: String {
        guard supportsReasoningControl else { return "Not supported" }
        guard isReasoningEnabled else { return "Off" }

        guard let reasoningType = selectedReasoningConfig?.type, reasoningType != .none else { return "Not supported" }

        switch reasoningType {
        case .budget:
            guard let budgetTokens = controls.reasoning?.budgetTokens else { return "On" }
            switch budgetTokens {
            case 1024: return "Low"
            case 2048: return "Medium"
            case 4096: return "High"
            case 8192: return "Extreme"
            default: return "\(budgetTokens) tokens"
            }
        case .effort:
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
                switch providerType {
                case .vertexai:
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

                case .anthropic, .xai, .cerebras, .none:
                    EmptyView()
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
                    let current = controls.reasoning?.budgetTokens ?? reasoningConfig.defaultBudget ?? 2048
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
            get: { controls.webSearch?.enabled ?? false },
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
        if controls.webSearch?.enabled == true {
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
            case .anthropic, .vertexai, .fireworks, .cerebras, .none:
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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(controls.providerSpecific),
           let json = String(data: data, encoding: .utf8) {
            providerSpecificParamsDraft = json
        } else {
            providerSpecificParamsDraft = controls.providerSpecific.isEmpty ? "{}" : "{}"
        }

        showingProviderSpecificParamsSheet = true
    }

    private var isProviderSpecificParamsDraftValid: Bool {
        let trimmed = providerSpecificParamsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONDecoder().decode([String: AnyCodable].self, from: data)) != nil
    }

    @discardableResult
    private func applyProviderSpecificParamsDraft() -> Bool {
        let trimmed = providerSpecificParamsDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            controls.providerSpecific = [:]
            persistControlsToConversation()
            providerSpecificParamsError = nil
            return true
        }

        do {
            guard let data = trimmed.data(using: .utf8) else {
                throw NSError(domain: "ProviderParams", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 JSON."])
            }
            controls.providerSpecific = try JSONDecoder().decode([String: AnyCodable].self, from: data)
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

    private func persistControlsToConversation() {
        do {
            conversationEntity.modelConfigData = try JSONEncoder().encode(controls)
            conversationEntity.updatedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func setReasoningOff() {
        updateReasoning { reasoning in
            reasoning.enabled = false
        }
        persistControlsToConversation()
    }

    private func setReasoningOn() {
        updateReasoning { reasoning in
            reasoning.enabled = true
        }
        persistControlsToConversation()
    }

    private func setReasoningEffort(_ effort: ReasoningEffort) {
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
        persistControlsToConversation()
    }

    private var thinkingBudgetDraftInt: Int? {
        Int(thinkingBudgetDraft.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var maxTokensDraftInt: Int? {
        let trimmed = maxTokensDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private var thinkingBudgetValidationWarning: String? {
        guard providerType == .anthropic else { return nil }
        guard let budget = thinkingBudgetDraftInt else { return "Enter an integer token budget (e.g., 10000)." }

        if budget <= 0 {
            return "Thinking budget must be a positive integer."
        }

        if let maxTokens = maxTokensDraftInt, maxTokens > 0, budget >= maxTokens {
            return "Note: Anthropic recommends budget_tokens < max_tokens unless using tools + interleaved thinking."
        }

        return "Tip: For Claude 3.7+ / 4.x, max_tokens is a strict limit and includes thinking tokens when enabled."
    }

    private func openThinkingBudgetEditor() {
        let budget = controls.reasoning?.budgetTokens
            ?? selectedReasoningConfig?.defaultBudget
            ?? 2048
        thinkingBudgetDraft = "\(budget)"
        maxTokensDraft = controls.maxTokens.map(String.init) ?? ""
        showingThinkingBudgetSheet = true
    }

    private func applyThinkingBudgetDraft() {
        guard let budgetTokens = thinkingBudgetDraftInt else { return }
        setAnthropicThinkingBudget(budgetTokens)
        controls.maxTokens = maxTokensDraftInt
        persistControlsToConversation()
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
        case .xai:
            return WebSearchControls(enabled: true, contextSize: nil, sources: [.web])
        case .anthropic, .vertexai, .fireworks, .cerebras, .none:
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
        case .xai:
            controls.webSearch?.contextSize = nil
            let sources = controls.webSearch?.sources ?? []
            if sources.isEmpty {
                controls.webSearch?.sources = [.web]
            }
        case .anthropic, .vertexai, .fireworks, .cerebras, .none:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
        }
    }

    private func normalizeControlsForCurrentSelection() {
        // Ensure the stored controls remain valid when switching provider/model.
        let originalData = (try? JSONEncoder().encode(controls)) ?? Data()

        // Reasoning: enforce model's reasoning config expectations.
        if let reasoningConfig = selectedReasoningConfig {
            switch reasoningConfig.type {
            case .effort:
                if controls.reasoning?.enabled == true, controls.reasoning?.effort == nil {
                    updateReasoning { $0.effort = reasoningConfig.defaultEffort ?? .medium }
                }
                controls.reasoning?.budgetTokens = nil
                if providerType == .openai,
                   controls.reasoning?.enabled == true,
                   (controls.reasoning?.effort ?? ReasoningEffort.none) != ReasoningEffort.none,
                   controls.reasoning?.summary == nil {
                    controls.reasoning?.summary = .auto
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
        } else {
            // If we don't know, keep user's settings.
        }

        // OpenAI: only GPT-5.2 supports xhigh.
        if providerType == .openai, controls.reasoning?.effort == .xhigh, !isOpenAIGPT52SeriesModel {
            controls.reasoning?.effort = .high
        }

        // Web search defaults & provider-specific fields.
        if controls.webSearch?.enabled == true {
            ensureValidWebSearchDefaultsIfEnabled()
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

    struct MessageRow: View {
        let messageEntity: MessageEntity
        let maxBubbleWidth: CGFloat
        let assistantDisplayName: String
        let assistantIcon: String?
        let toolResultsByCallID: [String: ToolResult]
        let isRerunAllowed: Bool
        let isToolCallRerunning: (String) -> Bool
        let onRerunToolCall: (ToolCall) -> Void

        var body: some View {
            let isUser = messageEntity.role == "user"
            let isTool = messageEntity.role == "tool"

        HStack(alignment: .top, spacing: 0) {
            if isUser {
                Spacer()
            }

            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: 6) {
                    // Header (Sender Name)
                    HStack(spacing: 6) {
                        if !isUser && !isTool {
                            AssistantBadgeIcon(icon: assistantIcon)
                        }
                        Text(isUser ? "You" : (isTool ? "Tool Output" : assistantDisplayName))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        if isTool {
                            Image(systemName: "hammer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    // Message Content
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = try? messageEntity.toDomain() {
                            ForEach(Array(message.content.enumerated()), id: \.offset) { _, part in
                                ContentPartView(part: part)
                            }

                            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(toolCalls) { call in
                                        ToolCallView(
                                            toolCall: call,
                                            toolResult: toolResultsByCallID[call.id],
                                            isRerunning: isToolCallRerunning(call.id),
                                            rerunAllowed: isRerunAllowed,
                                            onRerun: { onRerunToolCall(call) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(bubbleBackground(isUser: isUser, isTool: isTool))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            
            if !isUser {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func bubbleBackground(isUser: Bool, isTool: Bool) -> Color {
        if isTool { return Color(nsColor: .controlBackgroundColor).opacity(0.5) }
        if isUser { return Color.accentColor.opacity(0.1) } // Very subtle blue tint
        return Color(nsColor: .controlBackgroundColor) // Standard blocks for assistant
    }
}

private struct AssistantBadgeIcon: View {
    let icon: String?

    var body: some View {
        Group {
            let trimmed = (icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            } else if trimmed.count <= 2 {
                Text(trimmed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: trimmed)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ContentPartView: View {
    let part: ContentPart

    var body: some View {
        switch part {
        case .text(let text):
            MessageTextView(text: text)

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

        case .file(let file):
            let row = HStack {
                Image(systemName: "doc")
                Text(file.filename)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

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
                    }
            }

        case .audio:
            Label("Audio content", systemImage: "waveform")
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func renderedImage(_ image: NSImage, fileURL: URL?) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 500)
            .cornerRadius(6)
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
    let isRerunning: Bool
    let rerunAllowed: Bool
    let onRerun: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hammer")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Text(displayTitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                statusPill

                if canRerun {
                    Button("Re-run") {
                        onRerun()
                    }
                    .font(.caption)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            if !isExpanded, let argumentSummary {
                Text("-> \(argumentSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
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

    private var canRerun: Bool {
        rerunAllowed && toolResult != nil && !isRerunning
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
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var durationText: String? {
        guard let toolResult, !isRerunning else { return nil }
        guard let seconds = toolResult.durationSeconds, seconds > 0 else { return nil }
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return "\(Int(seconds.rounded()))s"
    }

    private var resolvedStatus: ToolCallStatus {
        if isRerunning { return .running }
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
        VStack(alignment: .leading, spacing: 6) {
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
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct StreamingMessageView: View {
    @ObservedObject var state: StreamingMessageState
    let maxBubbleWidth: CGFloat
    let assistantDisplayName: String
    let assistantIcon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ConstrainedWidth(maxBubbleWidth) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AssistantBadgeIcon(icon: assistantIcon)
                        Text(assistantDisplayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        if !state.thinkingContent.isEmpty {
                            DisclosureGroup(isExpanded: .constant(true)) {
                                Text(state.thinkingContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                            } label: {
                                HStack {
                                    ProgressView().scaleEffect(0.5)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !state.textContent.isEmpty {
                            MessageTextView(text: state.textContent, mode: .plainText)
                        } else if state.thinkingContent.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5)
                                Text("Generating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

class StreamingMessageState: ObservableObject, Equatable {
    @Published var textContent = ""
    @Published var thinkingContent = ""
    static func == (lhs: StreamingMessageState, rhs: StreamingMessageState) -> Bool {
        lhs.textContent == rhs.textContent && lhs.thinkingContent == rhs.thinkingContent
    }
}
