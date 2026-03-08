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

    static func makeRenderContext(
        from orderedMessages: [MessageEntity],
        fallbackModelLabel: String,
        assistantProviderIconID: (String) -> String?
    ) -> ChatThreadRenderContext {
        var messageEntitiesByID: [UUID: MessageEntity] = [:]
        messageEntitiesByID.reserveCapacity(orderedMessages.count)

        var renderedItems: [MessageRenderItem] = []
        renderedItems.reserveCapacity(orderedMessages.count)

        for entity in orderedMessages {
            messageEntitiesByID[entity.id] = entity
            guard entity.role != "tool" else { continue }

            guard let message = try? entity.toDomain() else { continue }
            renderedItems.append(
                MessageRenderItem(
                    id: entity.id,
                    contextThreadID: entity.contextThreadID,
                    role: entity.role,
                    timestamp: entity.timestamp,
                    renderedContentParts: renderedContentParts(content: message.content),
                    toolCalls: message.toolCalls ?? [],
                    searchActivities: message.searchActivities ?? [],
                    codexToolActivities: message.codexToolActivities ?? [],
                    assistantModelLabel: entity.role == "assistant"
                        ? (entity.generatedModelName ?? entity.generatedModelID ?? fallbackModelLabel)
                        : nil,
                    assistantProviderIconID: entity.role == "assistant"
                        ? assistantProviderIconID(entity.generatedProviderID ?? "")
                        : nil,
                    responseMetrics: entity.responseMetrics,
                    copyText: copyableText(from: message),
                    canEditUserMessage: entity.role == "user"
                        && message.content.contains(where: { part in
                            if case .text = part { return true }
                            return false
                        }),
                    perMessageMCPServerNames: message.perMessageMCPServerNames ?? []
                )
            )
        }

        return ChatThreadRenderContext(
            visibleMessages: renderedItems,
            messageEntitiesByID: messageEntitiesByID,
            toolResultsByCallID: toolResultsByToolCallID(in: orderedMessages)
        )
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

    private static func renderedContentParts(content: [ContentPart]) -> [RenderedMessageContentPart] {
        content.compactMap { part in
            if case .redactedThinking = part {
                return nil
            }
            return RenderedMessageContentPart(part: part)
        }
    }

    private static func copyableText(from message: Message) -> String {
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
}
