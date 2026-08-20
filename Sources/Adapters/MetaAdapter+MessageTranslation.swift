import Foundation

extension MetaAdapter {
    func translateInput(_ messages: [Message], allowNativePDF: Bool) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .tool:
                if let toolResults = message.toolResults {
                    for result in toolResults {
                        items.append(MetaResponsesInputSupport.functionCallOutputItem(result))
                    }
                }

            case .system, .user:
                if let translated = try await translateMessage(message, allowNativePDF: allowNativePDF) {
                    items.append(translated)
                }

            case .assistant:
                try await appendAssistantTurn(
                    message,
                    allowNativePDF: allowNativePDF,
                    to: &items
                )
            }
        }

        return items
    }

    /// Emits a Meta-valid assistant turn:
    /// 1. Encrypted `reasoning` items (from Meta redactedThinking)
    /// 2. Assistant message content (text/images/…) when present
    /// 3. `function_call` items
    ///
    /// Conversation structure (Meta docs): every reasoning item must be followed by
    /// an assistant message or a function_call before the next user/system/developer
    /// message. When the model produced reasoning with neither text nor tools, insert
    /// a minimal empty assistant message.
    private func appendAssistantTurn(
        _ message: Message,
        allowNativePDF: Bool,
        to items: inout [[String: Any]]
    ) async throws {
        let reasoningItems = metaReasoningReplayItems(from: message)
        items.append(contentsOf: reasoningItems)

        let messageItem = try await translateMessage(message, allowNativePDF: allowNativePDF)
        if let messageItem {
            items.append(messageItem)
        }

        let toolCalls = message.toolCalls ?? []
        if !toolCalls.isEmpty {
            items.append(contentsOf: toolCalls.map(MetaResponsesInputSupport.functionCallItem))
        }

        if let toolResults = message.toolResults {
            for result in toolResults {
                items.append(MetaResponsesInputSupport.functionCallOutputItem(result))
            }
        }

        // Reasoning without a follower would make the next user turn HTTP 400.
        if !reasoningItems.isEmpty, messageItem == nil, toolCalls.isEmpty {
            items.append(MetaResponsesInputSupport.emptyAssistantMessageItem())
        }
    }

    private func metaReasoningReplayItems(from message: Message) -> [[String: Any]] {
        guard message.role == .assistant else { return [] }

        var out: [[String: Any]] = []
        out.reserveCapacity(2)

        for part in message.content {
            guard case .redactedThinking(let redacted) = part else { continue }
            // Only Muse Spark encrypted blobs are valid for replay. Native Meta
            // tags `meta`; OpenCode Go's accumulator tags `opencodeGo`. Skip
            // foreign (e.g. Anthropic) or legacy untagged blocks.
            guard MetaResponsesInputSupport.isMuseSparkReasoningReplayProvider(redacted.provider) else { continue }
            guard let encrypted = redacted.data.trimmedNonEmpty else { continue }
            out.append(
                MetaResponsesInputSupport.reasoningReplayItem(
                    encryptedContent: encrypted,
                    id: redacted.id
                )
            )
        }

        return out
    }

    private func translateMessage(_ message: Message, allowNativePDF: Bool) async throws -> [String: Any]? {
        var content: [[String: Any]] = []
        for part in message.content {
            if let translated = try await translateContentPart(
                part,
                role: message.role,
                allowNativePDF: allowNativePDF
            ) {
                content.append(translated)
            }
        }

        guard !content.isEmpty else { return nil }

        return [
            "role": message.role.rawValue,
            "content": content
        ]
    }

    private func translateContentPart(
        _ part: ContentPart,
        role: MessageRole,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
        switch part {
        case .text(let text):
            return MetaResponsesInputSupport.textContentPart(text, role: role)
        case .quote(let quote):
            return MetaResponsesInputSupport.textContentPart(quote.quotedText, role: role)

        case .image(let image):
            return try await translateImage(image)

        case .file(let file):
            return try await translateFile(file, role: role, allowNativePDF: allowNativePDF)

        case .video(let video):
            return try await translateVideo(video, role: role)

        case .audio(let audio):
            guard role == .user else { return nil }
            return try await translateAudio(audio, role: role)

        case .thinking, .redactedThinking:
            // Visible thinking text is not a Meta Responses reasoning item.
            // Encrypted CoT is emitted as top-level `reasoning` items in
            // `appendAssistantTurn` (never inside message content).
            return nil
        }
    }

    private func translateImage(_ image: ImageContent) async throws -> [String: Any]? {
        if let data = image.data {
            if data.count > Self.inlineMediaByteLimit {
                if let hosted = try await uploadHostedMedia(
                    data: data,
                    filename: "image.\(imageFileExtension(for: image.mimeType))",
                    mimeType: image.mimeType
                ) {
                    return MetaResponsesInputSupport.imageContentPart(fileID: hosted.id)
                }
            }
            return MetaResponsesInputSupport.imageContentPart(
                imageURL: mediaDataURI(mimeType: image.mimeType, data: data)
            )
        }

        if let url = image.url {
            if url.isFileURL {
                let data = try resolveFileData(from: url)
                if data.count > Self.inlineMediaByteLimit {
                    if let hosted = try await uploadHostedMedia(
                        data: data,
                        filename: url.lastPathComponent,
                        mimeType: image.mimeType
                    ) {
                        return MetaResponsesInputSupport.imageContentPart(fileID: hosted.id)
                    }
                }
                return MetaResponsesInputSupport.imageContentPart(
                    imageURL: mediaDataURI(mimeType: image.mimeType, data: data)
                )
            }
            return MetaResponsesInputSupport.imageContentPart(imageURL: url.absoluteString)
        }

        return nil
    }

    private func translateFile(
        _ file: FileContent,
        role: MessageRole,
        allowNativePDF: Bool
    ) async throws -> [String: Any]? {
        let mime = normalizedMIMEType(file.mimeType)
        let isPDF = MetaResponsesInputSupport.isPDF(mime)

        if isPDF, !allowNativePDF {
            return MetaResponsesInputSupport.fallbackFileContentPart(file: file, role: role)
        }

        if let url = file.url, !url.isFileURL {
            return MetaResponsesInputSupport.remoteFileContentPart(url: url)
        }

        let fileData: Data?
        if let data = file.data {
            fileData = data
        } else if let url = file.url, url.isFileURL {
            fileData = try resolveFileData(from: url)
        } else {
            fileData = nil
        }

        guard let fileData else {
            return MetaResponsesInputSupport.fallbackFileContentPart(file: file, role: role)
        }

        if fileData.count > Self.inlineMediaByteLimit {
            if let hosted = try await uploadHostedMedia(
                data: fileData,
                filename: file.filename,
                mimeType: mime
            ) {
                return MetaResponsesInputSupport.hostedFileContentPart(
                    fileID: hosted.id,
                    filename: file.filename
                )
            }
        }

        return MetaResponsesInputSupport.inlineFileContentPart(
            filename: file.filename,
            mimeType: mime,
            data: fileData
        )
    }

    private func translateVideo(_ video: VideoContent, role: MessageRole) async throws -> [String: Any]? {
        guard role == .user else { return nil }

        if let url = video.url, !url.isFileURL {
            return MetaResponsesInputSupport.videoContentPart(videoURL: url.absoluteString)
        }

        let data: Data?
        if let videoData = video.data {
            data = videoData
        } else if let url = video.url, url.isFileURL {
            data = try resolveFileData(from: url)
        } else {
            data = nil
        }

        guard let data else {
            return MetaResponsesInputSupport.textContentPart(
                unsupportedVideoInputNotice(video, providerName: "Meta"),
                role: role
            )
        }

        let mime = video.mimeType.isEmpty ? "video/mp4" : video.mimeType
        if data.count > Self.inlineMediaByteLimit {
            if let hosted = try await uploadHostedMedia(
                data: data,
                filename: "video.\(videoFileExtension(for: mime))",
                mimeType: mime
            ) {
                return MetaResponsesInputSupport.videoContentPart(fileID: hosted.id)
            }
        }

        return MetaResponsesInputSupport.videoContentPart(
            videoURL: mediaDataURI(mimeType: mime, data: data)
        )
    }

    private func translateAudio(_ audio: AudioContent, role: MessageRole) async throws -> [String: Any]? {
        let mime = audio.mimeType.isEmpty ? "audio/wav" : audio.mimeType

        let data: Data?
        if let audioData = audio.data {
            data = audioData
        } else if let url = audio.url, url.isFileURL {
            data = try resolveFileData(from: url)
        } else if let url = audio.url, !url.isFileURL {
            return MetaResponsesInputSupport.remoteFileContentPart(url: url)
        } else {
            data = nil
        }

        guard let data else { return nil }

        let filename = "audio.\(audioFileExtension(for: mime))"
        if data.count > Self.inlineMediaByteLimit {
            if let hosted = try await uploadHostedMedia(
                data: data,
                filename: filename,
                mimeType: mime
            ) {
                return MetaResponsesInputSupport.hostedFileContentPart(
                    fileID: hosted.id,
                    filename: filename
                )
            }
        }

        return MetaResponsesInputSupport.inlineFileContentPart(
            filename: filename,
            mimeType: mime,
            data: data
        )
    }

    private func uploadHostedMedia(
        data: Data,
        filename: String,
        mimeType: String
    ) async throws -> HostedProviderFileReference? {
        // OpenCode Go exposes `/responses` but not Meta's `/files` upload. A failed
        // hosted upload rethrows and kills the send — skip it and use inline data.
        guard providerConfig.type == .meta else { return nil }

        do {
            return try await ProviderHostedFileStore.shared.uploadMetaFile(
                data: data,
                filename: filename,
                mimeType: mimeType,
                baseURL: baseURL,
                apiKey: apiKey,
                networkManager: networkManager
            )
        } catch {
            if shouldFallbackFromHostedFileUpload(error) {
                return nil
            }
            throw error
        }
    }

    private func imageFileExtension(for mimeType: String) -> String {
        switch normalizedMIMEType(mimeType) {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        default: return "png"
        }
    }

    private func videoFileExtension(for mimeType: String) -> String {
        switch normalizedMIMEType(mimeType) {
        case "video/mp4": return "mp4"
        case "video/webm": return "webm"
        case "video/quicktime": return "mov"
        default: return "mp4"
        }
    }

    private func audioFileExtension(for mimeType: String) -> String {
        switch normalizedMIMEType(mimeType) {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/wav", "audio/x-wav": return "wav"
        default: return "wav"
        }
    }
}
