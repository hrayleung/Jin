import Foundation

struct ChatRenderContextBatch {
    let activeThreadID: UUID?
    let activeContext: ChatThreadRenderContext
    let contextsByThreadID: [UUID: ChatThreadRenderContext]
}

enum ChatRenderContextBatchBuilder {
    static func makeBatch(
        allMessages: [MessageEntity],
        activeThreadID: UUID?,
        selectedThreads: [ConversationModelThreadEntity],
        activeContext: ChatThreadRenderContext,
        modelNameForThread: (ConversationModelThreadEntity) -> String,
        assistantProviderIconID: (String) -> String?
    ) -> ChatRenderContextBatch {
        var contextsByThreadID: [UUID: ChatThreadRenderContext] = [:]
        contextsByThreadID.reserveCapacity(selectedThreads.count)

        for thread in selectedThreads {
            if thread.id == activeThreadID {
                contextsByThreadID[thread.id] = activeContext
                continue
            }

            contextsByThreadID[thread.id] = makeContext(
                allMessages: allMessages,
                threadID: thread.id,
                fallbackModelLabel: modelNameForThread(thread),
                assistantProviderIconID: assistantProviderIconID
            )
        }

        if let activeThreadID, contextsByThreadID[activeThreadID] == nil {
            contextsByThreadID[activeThreadID] = activeContext
        }

        return ChatRenderContextBatch(
            activeThreadID: activeThreadID,
            activeContext: activeContext,
            contextsByThreadID: contextsByThreadID
        )
    }

    static func makeFallbackContext(
        visibleMessages: [MessageRenderItem],
        historyMessages: [Message],
        messageEntitiesByID: [UUID: MessageEntity],
        toolResultsByCallID: [String: ToolResult],
        artifactCatalog: ArtifactCatalog
    ) -> ChatThreadRenderContext {
        ChatThreadRenderContext(
            visibleMessages: visibleMessages,
            historyMessages: historyMessages,
            messageEntitiesByID: messageEntitiesByID,
            toolResultsByCallID: toolResultsByCallID,
            artifactCatalog: artifactCatalog
        )
    }

    static func makeContext(
        allMessages: [MessageEntity],
        threadID: UUID,
        fallbackModelLabel: String,
        assistantProviderIconID: (String) -> String?
    ) -> ChatThreadRenderContext {
        let ordered = ChatMessageRenderPipeline.orderedMessages(
            from: allMessages,
            threadID: threadID
        )
        return ChatMessageRenderPipeline.makeRenderContext(
            from: ordered,
            fallbackModelLabel: fallbackModelLabel,
            assistantProviderIconID: assistantProviderIconID
        )
    }
}
