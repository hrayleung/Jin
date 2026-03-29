import Collections
import Foundation

enum ChatMessageRenderPipeline {
    private static let asyncBuildMessageCountThreshold = 80
    private static let asyncBuildTotalPayloadByteThreshold = 32_000
    private static let asyncBuildSingleMessagePayloadByteThreshold = 12_000

    static func orderedMessages(from messages: [MessageEntity], threadID: UUID? = nil) -> [MessageEntity] {
        let filtered = messages.filter { entity in
            guard let threadID else { return true }
            return entity.contextThreadID == threadID
        }

        return filtered.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func shouldBuildRenderContextAsynchronously(from orderedMessages: [MessageEntity]) -> Bool {
        guard !orderedMessages.isEmpty else { return false }

        var totalPayloadBytes = 0
        var largestMessagePayloadBytes = 0

        for entity in orderedMessages {
            let payloadBytes = estimatedPayloadBytes(for: entity)
            totalPayloadBytes += payloadBytes
            largestMessagePayloadBytes = max(largestMessagePayloadBytes, payloadBytes)
        }

        return orderedMessages.count >= asyncBuildMessageCountThreshold
            || totalPayloadBytes >= asyncBuildTotalPayloadByteThreshold
            || largestMessagePayloadBytes >= asyncBuildSingleMessagePayloadByteThreshold
    }

    static func makeRenderContext(
        from orderedMessages: [MessageEntity],
        fallbackModelLabel: String,
        assistantProviderIconID: (String) -> String?
    ) -> ChatThreadRenderContext {
        var messageEntitiesByID: [UUID: MessageEntity] = [:]
        messageEntitiesByID.reserveCapacity(orderedMessages.count)

        var renderedItems: [MessageRenderItem] = []
        renderedItems.reserveCapacity(orderedMessages.count)
        var historyMessages: [Message] = []
        historyMessages.reserveCapacity(orderedMessages.count)

        var artifactVersionCounts: [String: Int] = [:]
        var artifactVersionsByID: OrderedDictionary<String, [RenderedArtifactVersion]> = [:]

        for entity in orderedMessages {
            messageEntitiesByID[entity.id] = entity
            guard let message = try? entity.toDomain() else { continue }
            historyMessages.append(message)
            guard entity.role != "tool",
                  let messageRole = MessageRole(rawValue: entity.role) else { continue }
            let renderedContent = renderedContentParts(
                from: message.content,
                messageID: entity.id
            )
            let renderedBlocks = renderedBlocks(
                content: renderedContent,
                role: messageRole,
                messageID: entity.id,
                timestamp: entity.timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID
            )
            let copyText = copyableText(from: renderedContent, role: messageRole)
            let renderMetadata = renderMetadata(
                role: messageRole,
                content: renderedContent,
                renderedBlocks: renderedBlocks,
                copyText: copyText
            )
            let toolCalls = message.toolCalls ?? []
            let searchActivities = message.searchActivities ?? []
            let codeExecutionActivities = message.codeExecutionActivities ?? []
            let codexToolActivities = message.codexToolActivities ?? []
            let agentToolActivities = message.agentToolActivities ?? []

            renderedItems.append(
                MessageRenderItem(
                    id: entity.id,
                    contextThreadID: entity.contextThreadID,
                    role: entity.role,
                    timestamp: entity.timestamp,
                    renderedBlocks: renderedBlocks,
                    toolCalls: toolCalls,
                    searchActivities: searchActivities,
                    codeExecutionActivities: codeExecutionActivities,
                    codexToolActivities: codexToolActivities,
                    agentToolActivities: agentToolActivities,
                    assistantModelLabel: entity.role == "assistant"
                        ? (entity.generatedModelName ?? entity.generatedModelID ?? fallbackModelLabel)
                        : nil,
                    assistantProviderIconID: entity.role == "assistant"
                        ? assistantProviderIconID(entity.generatedProviderID ?? "")
                        : nil,
                    responseMetrics: entity.responseMetrics,
                    copyText: copyText,
                    preferredRenderMode: renderMetadata.preferredRenderMode,
                    isMemoryIntensiveAssistantContent: renderMetadata.isMemoryIntensiveAssistantContent,
                    collapsedPreview: renderMetadata.collapsedPreview,
                    canEditUserMessage: entity.role == "user"
                        && renderedContent.contains(where: { part in
                            if case .text = part { return true }
                            return false
                        }),
                    canDeleteResponse: entity.role == MessageRole.user.rawValue
                        && ChatMessageEditingSupport.messagesToDeleteForResponse(
                            afterUserMessage: entity,
                            orderedMessages: orderedMessages
                        ) != nil,
                    perMessageMCPServerNames: message.perMessageMCPServerNames ?? []
                )
            )
        }

        return ChatThreadRenderContext(
            visibleMessages: renderedItems,
            historyMessages: historyMessages,
            messageEntitiesByID: messageEntitiesByID,
            toolResultsByCallID: toolResultsByToolCallID(in: orderedMessages),
            artifactCatalog: ArtifactCatalog(
                orderedArtifactIDs: Array(artifactVersionsByID.keys),
                versionsByArtifactID: Dictionary(uniqueKeysWithValues: artifactVersionsByID.map { ($0.key, $0.value) })
            )
        )
    }

    static func makeDecodedRenderContext(
        from orderedMessages: [PersistedMessageSnapshot],
        fallbackModelLabel: String,
        assistantProviderIconsByID: [String: String?]
    ) -> ChatDecodedRenderContext {
        var renderedItems: [MessageRenderItem] = []
        renderedItems.reserveCapacity(orderedMessages.count)

        var artifactVersionCounts: [String: Int] = [:]
        var artifactVersionsByID: OrderedDictionary<String, [RenderedArtifactVersion]> = [:]
        let decoder = JSONDecoder()

        for snapshot in orderedMessages {
            if Task.isCancelled {
                break
            }
            guard snapshot.role != "tool",
                  let messageRole = MessageRole(rawValue: snapshot.role),
                  let renderedContent = renderedContentParts(
                    from: snapshot.contentData,
                    messageID: snapshot.id
                  ) else {
                continue
            }

            let renderedBlocks = renderedBlocks(
                content: renderedContent,
                role: messageRole,
                messageID: snapshot.id,
                timestamp: snapshot.timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID
            )
            let copyText = copyableText(from: renderedContent, role: messageRole)
            let renderMetadata = renderMetadata(
                role: messageRole,
                content: renderedContent,
                renderedBlocks: renderedBlocks,
                copyText: copyText
            )
            let toolCalls = snapshot.toolCallsData.flatMap { try? decoder.decode([ToolCall].self, from: $0) } ?? []
            let searchActivities = snapshot.searchActivitiesData.flatMap {
                try? decoder.decode([SearchActivity].self, from: $0)
            } ?? []
            let codeExecutionActivities = snapshot.codeExecutionActivitiesData.flatMap {
                try? decoder.decode([CodeExecutionActivity].self, from: $0)
            } ?? []
            let codexToolActivities = snapshot.codexToolActivitiesData.flatMap {
                try? decoder.decode([CodexToolActivity].self, from: $0)
            } ?? []
            let agentToolActivities = snapshot.agentToolActivitiesData.flatMap {
                try? decoder.decode([CodexToolActivity].self, from: $0)
            } ?? []
            let perMessageMCPServerNames = snapshot.perMessageMCPServerNamesData.flatMap {
                try? decoder.decode([String].self, from: $0)
            } ?? []

            renderedItems.append(
                MessageRenderItem(
                    id: snapshot.id,
                    contextThreadID: snapshot.contextThreadID,
                    role: snapshot.role,
                    timestamp: snapshot.timestamp,
                    renderedBlocks: renderedBlocks,
                    toolCalls: toolCalls,
                    searchActivities: searchActivities,
                    codeExecutionActivities: codeExecutionActivities,
                    codexToolActivities: codexToolActivities,
                    agentToolActivities: agentToolActivities,
                    assistantModelLabel: snapshot.role == "assistant"
                        ? (snapshot.generatedModelName ?? snapshot.generatedModelID ?? fallbackModelLabel)
                        : nil,
                    assistantProviderIconID: snapshot.role == "assistant"
                        ? (assistantProviderIconsByID[snapshot.generatedProviderID ?? ""] ?? nil)
                        : nil,
                    responseMetrics: snapshot.responseMetrics(using: decoder),
                    copyText: copyText,
                    preferredRenderMode: renderMetadata.preferredRenderMode,
                    isMemoryIntensiveAssistantContent: renderMetadata.isMemoryIntensiveAssistantContent,
                    collapsedPreview: renderMetadata.collapsedPreview,
                    canEditUserMessage: snapshot.role == "user"
                        && renderedContent.contains(where: { part in
                            if case .text = part { return true }
                            return false
                        }),
                    canDeleteResponse: snapshot.role == MessageRole.user.rawValue
                        && messagesToDeleteForResponse(
                            afterUserMessage: snapshot,
                            orderedMessages: orderedMessages
                        ) != nil,
                    perMessageMCPServerNames: perMessageMCPServerNames
                )
            )
        }

        return ChatDecodedRenderContext(
            visibleMessages: renderedItems,
            historyMessages: [],
            toolResultsByCallID: toolResultsByToolCallID(in: orderedMessages),
            artifactCatalog: ArtifactCatalog(
                orderedArtifactIDs: Array(artifactVersionsByID.keys),
                versionsByArtifactID: Dictionary(uniqueKeysWithValues: artifactVersionsByID.map { ($0.key, $0.value) })
            )
        )
    }

    static func decodeHistoryMessages(from orderedMessages: [PersistedMessageSnapshot]) -> [Message] {
        let decoder = JSONDecoder()
        var historyMessages: [Message] = []
        historyMessages.reserveCapacity(orderedMessages.count)

        for snapshot in orderedMessages {
            if Task.isCancelled {
                break
            }
            if let historyMessage = snapshot.toDomain(using: decoder) {
                historyMessages.append(historyMessage)
            }
        }

        return historyMessages
    }

    static func editableUserText(from message: Message) -> String? {
        let parts = message.content.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    private static func renderedBlocks(
        content: [RenderedContentPart],
        role: MessageRole,
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>
    ) -> [RenderedMessageBlock] {
        var blocks: [RenderedMessageBlock] = []

        for part in content {
            switch part {
            case .redactedThinking:
                continue

            case .text(let text) where role == .assistant:
                let parseResult = ArtifactMarkupParser.parse(text)
                let segments = parseResult.visibleTextSegments
                let artifacts = parseResult.artifacts
                let maxIndex = max(segments.count, artifacts.count)

                for i in 0..<maxIndex {
                    if i < segments.count {
                        let segment = segments[i]
                        if !segment.isEmpty {
                            blocks.append(.content(.text(segment)))
                        }
                    }

                    if i < artifacts.count {
                        let artifact = artifacts[i]
                        let nextVersion = (artifactVersionCounts[artifact.artifactID] ?? 0) + 1
                        artifactVersionCounts[artifact.artifactID] = nextVersion

                        let version = RenderedArtifactVersion(
                            artifactID: artifact.artifactID,
                            version: nextVersion,
                            title: artifact.title,
                            contentType: artifact.contentType,
                            content: artifact.content,
                            sourceMessageID: messageID,
                            sourceTimestamp: timestamp
                        )
                        artifactVersionsByID[artifact.artifactID, default: []].append(version)
                        blocks.append(.artifact(version))
                    }
                }

            default:
                blocks.append(.content(part))
            }
        }

        return blocks
    }

    private static func messagesToDeleteForResponse(
        afterUserMessage message: PersistedMessageSnapshot,
        orderedMessages: [PersistedMessageSnapshot]
    ) -> [PersistedMessageSnapshot]? {
        guard let index = orderedMessages.firstIndex(where: { $0.id == message.id }) else { return nil }
        let startIndex = index + 1
        guard startIndex < orderedMessages.count else { return nil }

        var result: [PersistedMessageSnapshot] = []
        for i in startIndex..<orderedMessages.count {
            let msg = orderedMessages[i]
            if msg.role == MessageRole.user.rawValue { break }
            if msg.role == MessageRole.assistant.rawValue || msg.role == MessageRole.tool.rawValue {
                result.append(msg)
            }
        }

        return result.isEmpty ? nil : result
    }

    private static func copyableText(from content: [RenderedContentPart], role: MessageRole) -> String {
        let textParts = content.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            let sourceText: String
            if role == .assistant {
                sourceText = ArtifactMarkupParser.visibleText(from: text)
            } else {
                sourceText = text
            }
            let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if !textParts.isEmpty {
            return textParts.joined(separator: "\n\n")
        }

        let fileParts = content.compactMap { part -> String? in
            guard case .file(let file) = part else { return nil }
            let trimmed = file.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return fileParts.joined(separator: "\n")
    }

    private struct RenderMetadata {
        let preferredRenderMode: MessageRenderMode
        let isMemoryIntensiveAssistantContent: Bool
        let collapsedPreview: LightweightMessagePreview?
    }

    private static func renderMetadata(
        role: MessageRole,
        content: [RenderedContentPart],
        renderedBlocks: [RenderedMessageBlock],
        copyText: String
    ) -> RenderMetadata {
        guard role == .assistant else {
            return RenderMetadata(
                preferredRenderMode: .fullWeb,
                isMemoryIntensiveAssistantContent: false,
                collapsedPreview: nil
            )
        }

        let containsArtifact = renderedBlocks.contains { block in
            if case .artifact = block { return true }
            return false
        }
        let textParts = content.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            return ArtifactMarkupParser.visibleText(from: text)
        }
        let combinedText = textParts.joined(separator: "\n\n")
        let hasSingleTextPartOnly = renderedBlocks.count == 1
            && content.count == 1
            && content.allSatisfy { part in
                if case .text = part { return true }
                return false
            }
            && !containsArtifact

        let previewSourceText = collapsedPreviewSourceText(
            copyText: copyText,
            renderedBlocks: renderedBlocks
        )
        let lineCount = max(1, previewSourceText.components(separatedBy: .newlines).count)
        let containsCode = containsLikelyCode(in: combinedText)
        let containsRichMarkdown = containsLikelyRichMarkdown(in: combinedText) || containsArtifact
        let prefersNativeText = hasSingleTextPartOnly && !containsRichMarkdown
        let isMemoryIntensive = containsCode || copyText.count > 1_800 || lineCount > 18 || containsArtifact

        let preview = isMemoryIntensive
            ? makeCollapsedPreview(
                from: previewSourceText,
                containsCode: containsCode,
                lineCount: lineCount
            )
            : nil

        return RenderMetadata(
            preferredRenderMode: prefersNativeText ? .nativeText : .fullWeb,
            isMemoryIntensiveAssistantContent: isMemoryIntensive,
            collapsedPreview: preview
        )
    }

    private static func makeCollapsedPreview(
        from text: String,
        containsCode: Bool,
        lineCount: Int
    ) -> LightweightMessagePreview? {
        let headlineLimit = 120
        let bodyLimit = 240
        var headline: String?
        var body = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if headline == nil {
                headline = String(trimmed.prefix(headlineLimit))
                continue
            }

            guard body.count < bodyLimit else { break }
            let separator = body.isEmpty ? "" : " "
            let remainingBudget = bodyLimit - body.count - separator.count
            guard remainingBudget > 0 else { break }
            body += separator
            body += String(trimmed.prefix(remainingBudget))
        }

        guard let headline else { return nil }

        return LightweightMessagePreview(
            headline: headline,
            body: body,
            lineCount: lineCount,
            containsCode: containsCode
        )
    }

    private static func collapsedPreviewSourceText(
        copyText: String,
        renderedBlocks: [RenderedMessageBlock]
    ) -> String {
        let trimmedCopyText = copyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCopyText.isEmpty else { return copyText }

        let artifactLines = renderedBlocks.compactMap { block -> String? in
            guard case .artifact(let artifact) = block else { return nil }
            return "\(artifact.title)\n\(artifact.contentType.displayName) Artifact"
        }

        return artifactLines.joined(separator: "\n\n")
    }

    private static func containsLikelyCode(in text: String) -> Bool {
        if text.contains("```") { return true }
        let lines = text.components(separatedBy: .newlines)
        let indentedLineCount = lines.filter { line in
            line.hasPrefix("    ") || line.hasPrefix("\t")
        }.count
        return indentedLineCount >= 2
    }

    private static func containsLikelyRichMarkdown(in text: String) -> Bool {
        if text.contains("```") || text.contains("|") || text.contains("`") { return true }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#")
                || trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("> ")
                || trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    private static func toolResultsByToolCallID(in messageEntities: [MessageEntity]) -> [String: ToolResult] {
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

    private static func toolResultsByToolCallID(in messageSnapshots: [PersistedMessageSnapshot]) -> [String: ToolResult] {
        var results: [String: ToolResult] = [:]
        results.reserveCapacity(8)

        let decoder = JSONDecoder()
        for snapshot in messageSnapshots where snapshot.role == "tool" {
            if Task.isCancelled {
                break
            }
            guard let data = snapshot.toolResultsData,
                  let toolResults = try? decoder.decode([ToolResult].self, from: data) else {
                continue
            }

            for result in toolResults {
                results[result.toolCallID] = result
            }
        }

        return results
    }

    private static func renderedContentParts(
        from content: [ContentPart],
        messageID: UUID
    ) -> [RenderedContentPart] {
        content.enumerated().map { index, part in
            switch part {
            case .text(let text):
                return .text(text)
            case .image(let image):
                return .image(
                    RenderedImageContent(
                        mimeType: image.mimeType,
                        inlineData: image.data,
                        url: image.url,
                        assetDisposition: image.assetDisposition,
                        deferredSource: image.data == nil ? nil : DeferredMessagePartReference(
                            messageID: messageID,
                            partIndex: index
                        )
                    )
                )
            case .video(let video):
                return .video(video)
            case .file(let file):
                return .file(
                    RenderedFileContent(
                        mimeType: file.mimeType,
                        filename: file.filename,
                        url: file.url,
                        extractedText: file.extractedText,
                        hasDeferredExtractedText: false,
                        deferredSource: file.extractedText == nil ? nil : DeferredMessagePartReference(
                            messageID: messageID,
                            partIndex: index
                        )
                    )
                )
            case .audio(let audio):
                return .audio(audio)
            case .thinking(let thinking):
                return .thinking(thinking)
            case .redactedThinking(let thinking):
                return .redactedThinking(thinking)
            }
        }
    }

    private static func renderedContentParts(
        from contentData: Data,
        messageID: UUID
    ) -> [RenderedContentPart]? {
        guard let rawParts = (try? JSONSerialization.jsonObject(with: contentData)) as? [[String: Any]] else {
            return nil
        }

        var parts: [RenderedContentPart] = []
        parts.reserveCapacity(rawParts.count)

        for (index, rawPart) in rawParts.enumerated() {
            guard let type = rawPart["type"] as? String else { continue }
            let deferredSource = DeferredMessagePartReference(messageID: messageID, partIndex: index)

            switch type {
            case "text":
                guard let text = rawPart["text"] as? String else { continue }
                parts.append(.text(text))

            case "image":
                guard let image = rawPart["image"] as? [String: Any],
                      let mimeType = image["mimeType"] as? String else { continue }
                let url = url(from: image["url"])
                let hasInlineData = image.keys.contains("data") && !(image["data"] is NSNull)
                let assetDisposition = mediaAssetDisposition(
                    rawValue: image["assetDisposition"] as? String,
                    url: url,
                    hasInlineData: hasInlineData
                )
                parts.append(
                    .image(
                        RenderedImageContent(
                            mimeType: mimeType,
                            inlineData: nil,
                            url: url,
                            assetDisposition: assetDisposition,
                            deferredSource: hasInlineData ? deferredSource : nil
                        )
                    )
                )

            case "video":
                guard let video = rawPart["video"] as? [String: Any],
                      let mimeType = video["mimeType"] as? String else { continue }
                parts.append(
                    .video(
                        VideoContent(
                            mimeType: mimeType,
                            data: nil,
                            url: url(from: video["url"]),
                            assetDisposition: mediaAssetDisposition(
                                rawValue: video["assetDisposition"] as? String,
                                url: url(from: video["url"]),
                                hasInlineData: video.keys.contains("data") && !(video["data"] is NSNull)
                            )
                        )
                    )
                )

            case "file":
                guard let file = rawPart["file"] as? [String: Any],
                      let mimeType = file["mimeType"] as? String,
                      let filename = file["filename"] as? String else { continue }
                let extractedText = file["extractedText"] as? String
                let hasDeferredExtractedText = file.keys.contains("extractedText") && !(file["extractedText"] is NSNull)
                parts.append(
                    .file(
                        RenderedFileContent(
                            mimeType: mimeType,
                            filename: filename,
                            url: url(from: file["url"]),
                            extractedText: extractedText,
                            hasDeferredExtractedText: extractedText == nil && hasDeferredExtractedText,
                            deferredSource: extractedText == nil && hasDeferredExtractedText ? deferredSource : nil
                        )
                    )
                )

            case "audio":
                guard let audio = rawPart["audio"] as? [String: Any],
                      let mimeType = audio["mimeType"] as? String else { continue }
                parts.append(
                    .audio(
                        AudioContent(
                            mimeType: mimeType,
                            data: nil,
                            url: url(from: audio["url"])
                        )
                    )
                )

            case "thinking":
                guard let text = rawPart["thinking"] as? String else { continue }
                parts.append(
                    .thinking(
                        ThinkingBlock(
                            text: text,
                            signature: rawPart["signature"] as? String,
                            provider: rawPart["provider"] as? String
                        )
                    )
                )

            case "redactedThinking":
                guard let data = rawPart["redactedData"] as? String else { continue }
                parts.append(
                    .redactedThinking(
                        RedactedThinkingBlock(
                            data: data,
                            provider: rawPart["provider"] as? String
                        )
                    )
                )

            default:
                continue
            }
        }

        return parts
    }

    private static func url(from value: Any?) -> URL? {
        guard let string = value as? String else { return nil }
        return URL(string: string)
    }

    private static func mediaAssetDisposition(
        rawValue: String?,
        url: URL?,
        hasInlineData: Bool
    ) -> MediaAssetDisposition {
        if let rawValue,
           let disposition = MediaAssetDisposition(rawValue: rawValue) {
            return disposition
        }

        if hasInlineData || url?.isFileURL == true {
            return .managed
        }

        if url != nil {
            return .externalReference
        }

        return .managed
    }

    private static func estimatedPayloadBytes(for entity: MessageEntity) -> Int {
        let payloads: [Data?] = [
            entity.toolCallsData,
            entity.toolResultsData,
            entity.searchActivitiesData,
            entity.codeExecutionActivitiesData,
            entity.codexToolActivitiesData,
            entity.agentToolActivitiesData,
            entity.perMessageMCPServerNamesData,
            entity.responseMetricsData
        ]

        return entity.contentData.count + payloads.reduce(0) { partialResult, payload in
            partialResult + (payload?.count ?? 0)
        }
    }
}
