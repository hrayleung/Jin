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

        var artifactVersionCounts: [String: Int] = [:]
        var artifactOrder: [String] = []
        var artifactVersionsByID: [String: [RenderedArtifactVersion]] = [:]

        for entity in orderedMessages {
            messageEntitiesByID[entity.id] = entity
            guard entity.role != "tool" else { continue }

            guard let message = try? entity.toDomain() else { continue }
            let renderedBlocks = renderedBlocks(
                content: message.content,
                role: message.role,
                messageID: entity.id,
                timestamp: entity.timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactOrder: &artifactOrder,
                artifactVersionsByID: &artifactVersionsByID
            )
            renderedItems.append(
                MessageRenderItem(
                    id: entity.id,
                    contextThreadID: entity.contextThreadID,
                    role: entity.role,
                    timestamp: entity.timestamp,
                    renderedBlocks: renderedBlocks,
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
                    copyText: copyableText(from: message, role: message.role),
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
            toolResultsByCallID: toolResultsByToolCallID(in: orderedMessages),
            artifactCatalog: ArtifactCatalog(
                orderedArtifactIDs: artifactOrder,
                versionsByArtifactID: artifactVersionsByID
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
        var artifactOrder: [String] = []
        var artifactVersionsByID: [String: [RenderedArtifactVersion]] = [:]
        let decoder = JSONDecoder()

        for snapshot in orderedMessages {
            if Task.isCancelled {
                break
            }
            guard snapshot.role != "tool" else { continue }
            guard let message = snapshot.toDomain(using: decoder) else { continue }

            let renderedBlocks = renderedBlocks(
                content: message.content,
                role: message.role,
                messageID: snapshot.id,
                timestamp: snapshot.timestamp,
                artifactVersionCounts: &artifactVersionCounts,
                artifactOrder: &artifactOrder,
                artifactVersionsByID: &artifactVersionsByID
            )
            renderedItems.append(
                MessageRenderItem(
                    id: snapshot.id,
                    contextThreadID: snapshot.contextThreadID,
                    role: snapshot.role,
                    timestamp: snapshot.timestamp,
                    renderedBlocks: renderedBlocks,
                    toolCalls: message.toolCalls ?? [],
                    searchActivities: message.searchActivities ?? [],
                    codexToolActivities: message.codexToolActivities ?? [],
                    assistantModelLabel: snapshot.role == "assistant"
                        ? (snapshot.generatedModelName ?? snapshot.generatedModelID ?? fallbackModelLabel)
                        : nil,
                    assistantProviderIconID: snapshot.role == "assistant"
                        ? (assistantProviderIconsByID[snapshot.generatedProviderID ?? ""] ?? nil)
                        : nil,
                    responseMetrics: snapshot.responseMetrics(using: decoder),
                    copyText: copyableText(from: message, role: message.role),
                    canEditUserMessage: snapshot.role == "user"
                        && message.content.contains(where: { part in
                            if case .text = part { return true }
                            return false
                        }),
                    perMessageMCPServerNames: message.perMessageMCPServerNames ?? []
                )
            )
        }

        return ChatDecodedRenderContext(
            visibleMessages: renderedItems,
            toolResultsByCallID: toolResultsByToolCallID(in: orderedMessages),
            artifactCatalog: ArtifactCatalog(
                orderedArtifactIDs: artifactOrder,
                versionsByArtifactID: artifactVersionsByID
            )
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

    private static func renderedBlocks(
        content: [ContentPart],
        role: MessageRole,
        messageID: UUID,
        timestamp: Date,
        artifactVersionCounts: inout [String: Int],
        artifactOrder: inout [String],
        artifactVersionsByID: inout [String: [RenderedArtifactVersion]]
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

                        if artifactVersionsByID[artifact.artifactID] == nil {
                            artifactOrder.append(artifact.artifactID)
                            artifactVersionsByID[artifact.artifactID] = []
                        }

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

    private static func copyableText(from message: Message, role: MessageRole) -> String {
        let textParts = message.content.compactMap { part -> String? in
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
}
