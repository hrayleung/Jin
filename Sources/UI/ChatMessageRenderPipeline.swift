import Collections
import Foundation

enum ChatMessageRenderPipeline {
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
        ChatRenderPayloadHeuristics.shouldBuildRenderContextAsynchronously(from: orderedMessages)
    }

    static func decodedRenderContextDroppedVisibleMessages(
        _ decoded: ChatDecodedRenderContext,
        orderedMessages: [MessageEntity]
    ) -> Bool {
        decoded.visibleMessages.count != expectedVisibleMessageCount(from: orderedMessages)
    }

    static func expectedVisibleMessageCount(from orderedMessages: [MessageEntity]) -> Int {
        orderedMessages.reduce(into: 0) { count, entity in
            guard entity.role != MessageRole.tool.rawValue,
                  MessageRole(rawValue: entity.role) != nil else {
                return
            }
            count += 1
        }
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
            guard entity.role != MessageRole.tool.rawValue,
                  let messageRole = MessageRole(rawValue: entity.role) else {
                continue
            }

            let renderedContent = ChatRenderedContentDecoder.renderedContentParts(
                from: message.content,
                messageID: entity.id
            )
            let item = makeRenderItem(
                id: entity.id,
                contextThreadID: entity.contextThreadID,
                role: entity.role,
                timestamp: entity.timestamp,
                messageRole: messageRole,
                renderedContent: renderedContent,
                toolCalls: message.toolCalls ?? [],
                searchActivities: message.searchActivities ?? [],
                codeExecutionActivities: message.codeExecutionActivities ?? [],
                codexToolActivities: message.codexToolActivities ?? [],
                agentToolActivities: message.agentToolActivities ?? [],
                assistantModelLabel: entity.role == MessageRole.assistant.rawValue
                    ? (entity.generatedModelName ?? entity.generatedModelID ?? fallbackModelLabel)
                    : nil,
                assistantModelID: entity.role == MessageRole.assistant.rawValue ? entity.generatedModelID : nil,
                assistantProviderIconID: entity.role == MessageRole.assistant.rawValue
                    ? assistantProviderIconID(entity.generatedProviderID ?? "")
                    : nil,
                responseMetrics: entity.responseMetrics,
                highlightSnapshots: entity.highlightSnapshots,
                canDeleteResponse: entity.role == MessageRole.user.rawValue
                    && ChatMessageEditingSupport.messagesToDeleteForResponse(
                        afterUserMessage: entity,
                        orderedMessages: orderedMessages
                    ) != nil,
                perMessageMCPServerNames: message.perMessageMCPServerNames ?? [],
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID
            )
            renderedItems.append(item)
        }

        return ChatThreadRenderContext(
            visibleMessages: renderedItems,
            historyMessages: historyMessages,
            messageEntitiesByID: messageEntitiesByID,
            toolResultsByCallID: ChatToolResultIndexBuilder.toolResultsByToolCallID(in: orderedMessages),
            artifactCatalog: artifactCatalog(from: artifactVersionsByID)
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
            if Task.isCancelled { break }
            guard snapshot.role != MessageRole.tool.rawValue,
                  let messageRole = MessageRole(rawValue: snapshot.role),
                  let renderedContent = ChatRenderedContentDecoder.renderedContentParts(
                    from: snapshot.contentData,
                    messageID: snapshot.id
                  ) else {
                continue
            }

            let item = makeRenderItem(
                id: snapshot.id,
                contextThreadID: snapshot.contextThreadID,
                role: snapshot.role,
                timestamp: snapshot.timestamp,
                messageRole: messageRole,
                renderedContent: renderedContent,
                toolCalls: decode([ToolCall].self, from: snapshot.toolCallsData, using: decoder) ?? [],
                searchActivities: decode([SearchActivity].self, from: snapshot.searchActivitiesData, using: decoder) ?? [],
                codeExecutionActivities: decode([CodeExecutionActivity].self, from: snapshot.codeExecutionActivitiesData, using: decoder) ?? [],
                codexToolActivities: decode([CodexToolActivity].self, from: snapshot.codexToolActivitiesData, using: decoder) ?? [],
                agentToolActivities: decode([CodexToolActivity].self, from: snapshot.agentToolActivitiesData, using: decoder) ?? [],
                assistantModelLabel: snapshot.role == MessageRole.assistant.rawValue
                    ? (snapshot.generatedModelName ?? snapshot.generatedModelID ?? fallbackModelLabel)
                    : nil,
                assistantModelID: snapshot.role == MessageRole.assistant.rawValue ? snapshot.generatedModelID : nil,
                assistantProviderIconID: snapshot.role == MessageRole.assistant.rawValue
                    ? (assistantProviderIconsByID[snapshot.generatedProviderID ?? ""] ?? nil)
                    : nil,
                responseMetrics: snapshot.responseMetrics(using: decoder),
                highlightSnapshots: snapshot.highlightSnapshots,
                canDeleteResponse: snapshot.role == MessageRole.user.rawValue
                    && messagesToDeleteForResponse(
                        afterUserMessage: snapshot,
                        orderedMessages: orderedMessages
                    ) != nil,
                perMessageMCPServerNames: decode([String].self, from: snapshot.perMessageMCPServerNamesData, using: decoder) ?? [],
                artifactVersionCounts: &artifactVersionCounts,
                artifactVersionsByID: &artifactVersionsByID
            )
            renderedItems.append(item)
        }

        return ChatDecodedRenderContext(
            visibleMessages: renderedItems,
            historyMessages: [],
            toolResultsByCallID: ChatToolResultIndexBuilder.toolResultsByToolCallID(in: orderedMessages),
            artifactCatalog: artifactCatalog(from: artifactVersionsByID)
        )
    }

    static func decodeHistoryMessages(from orderedMessages: [PersistedMessageSnapshot]) -> [Message] {
        let decoder = JSONDecoder()
        var historyMessages: [Message] = []
        historyMessages.reserveCapacity(orderedMessages.count)

        for snapshot in orderedMessages {
            if Task.isCancelled { break }
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

    private static func makeRenderItem(
        id: UUID,
        contextThreadID: UUID?,
        role: String,
        timestamp: Date,
        messageRole: MessageRole,
        renderedContent: [RenderedContentPart],
        toolCalls: [ToolCall],
        searchActivities: [SearchActivity],
        codeExecutionActivities: [CodeExecutionActivity],
        codexToolActivities: [CodexToolActivity],
        agentToolActivities: [CodexToolActivity],
        assistantModelLabel: String?,
        assistantModelID: String?,
        assistantProviderIconID: String?,
        responseMetrics: ResponseMetrics?,
        highlightSnapshots: [MessageHighlightSnapshot],
        canDeleteResponse: Bool,
        perMessageMCPServerNames: [String],
        artifactVersionCounts: inout [String: Int],
        artifactVersionsByID: inout OrderedDictionary<String, [RenderedArtifactVersion]>
    ) -> MessageRenderItem {
        let renderedBlocks = ChatArtifactRenderBlockBuilder.renderedBlocks(
            content: renderedContent,
            role: messageRole,
            messageID: id,
            timestamp: timestamp,
            artifactVersionCounts: &artifactVersionCounts,
            artifactVersionsByID: &artifactVersionsByID
        )
        let copyText = ChatMessageRenderMetadataBuilder.copyableText(from: renderedContent, role: messageRole)
        let renderMetadata = ChatMessageRenderMetadataBuilder.renderMetadata(
            role: messageRole,
            content: renderedContent,
            renderedBlocks: renderedBlocks,
            copyText: copyText
        )

        return MessageRenderItem(
            id: id,
            contextThreadID: contextThreadID,
            role: role,
            timestamp: timestamp,
            renderedBlocks: renderedBlocks,
            toolCalls: toolCalls,
            searchActivities: searchActivities,
            codeExecutionActivities: codeExecutionActivities,
            codexToolActivities: codexToolActivities,
            agentToolActivities: agentToolActivities,
            assistantModelLabel: assistantModelLabel,
            assistantModelID: assistantModelID,
            assistantProviderIconID: assistantProviderIconID,
            responseMetrics: responseMetrics,
            highlights: highlightSnapshots,
            copyText: copyText,
            preferredRenderMode: renderMetadata.preferredRenderMode,
            isMemoryIntensiveAssistantContent: renderMetadata.isMemoryIntensiveAssistantContent,
            collapsedPreview: renderMetadata.collapsedPreview,
            canEditUserMessage: role == MessageRole.user.rawValue && renderedContent.contains(where: isTextPart),
            canDeleteResponse: canDeleteResponse,
            perMessageMCPServerNames: perMessageMCPServerNames
        )
    }

    private static func artifactCatalog(
        from artifactVersionsByID: OrderedDictionary<String, [RenderedArtifactVersion]>
    ) -> ArtifactCatalog {
        ArtifactCatalog(
            orderedArtifactIDs: Array(artifactVersionsByID.keys),
            versionsByArtifactID: Dictionary(uniqueKeysWithValues: artifactVersionsByID.map { ($0.key, $0.value) })
        )
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data?,
        using decoder: JSONDecoder
    ) -> Value? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func isTextPart(_ part: RenderedContentPart) -> Bool {
        if case .text = part { return true }
        return false
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
}
