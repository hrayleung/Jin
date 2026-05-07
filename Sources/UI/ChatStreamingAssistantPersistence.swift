import Foundation

extension ChatStreamingOrchestrator {
    struct AssistantPersistenceResult {
        let message: Message?
        let persistedMessageID: UUID?
        let hasRenderableContent: Bool
        let completionPreview: String?
    }

    struct CompletionNotificationState {
        private(set) var shouldNotify = false
        private(set) var preview: String?

        mutating func observe(_ result: AssistantPersistenceResult) {
            if let completionPreview = result.completionPreview {
                preview = completionPreview
            }
        }

        mutating func finishWithoutToolContinuation(hasRenderableContent: Bool) {
            shouldNotify = hasRenderableContent
        }
    }

    static func hasRenderableAssistantContent(
        assistantPartCount: Int,
        searchActivityCount: Int,
        codeExecutionActivityCount: Int,
        codexToolActivityCount: Int,
        agentToolActivityCount: Int = 0
    ) -> Bool {
        assistantPartCount > 0
            || searchActivityCount > 0
            || codeExecutionActivityCount > 0
            || codexToolActivityCount > 0
            || agentToolActivityCount > 0
    }

    static func persistAssistantOutput(
        response: StreamingResponseSnapshot,
        responseMetrics: ResponseMetrics?,
        context ctx: SessionContext,
        callbacks: SessionCallbacks
    ) async -> AssistantPersistenceResult {
        let hasRenderableContent = response.hasRenderableAssistantContent

        guard hasRenderableContent || !response.toolCalls.isEmpty else {
            return AssistantPersistenceResult(
                message: nil,
                persistedMessageID: nil,
                hasRenderableContent: false,
                completionPreview: nil
            )
        }

        let persistedParts = await AttachmentImportPipeline.persistImagesToDisk(response.assistantParts)
        let assistantMessage = Message(
            role: .assistant,
            content: persistedParts,
            toolCalls: response.toolCalls.isEmpty ? nil : response.toolCalls,
            searchActivities: response.searchActivities.isEmpty ? nil : response.searchActivities,
            codeExecutionActivities: response.codeExecutionActivities.isEmpty ? nil : response.codeExecutionActivities,
            codexToolActivities: response.codexToolActivities.isEmpty ? nil : response.codexToolActivities,
            agentToolActivities: response.agentToolActivities.isEmpty ? nil : response.agentToolActivities
        )
        let completionPreview = AttachmentImportPipeline.completionNotificationPreview(from: persistedParts)

        let persistedAssistantMessageID = await MainActor.run {
            callbacks.persistAssistantMessage(
                assistantMessage,
                ctx.providerID,
                ctx.modelID,
                ctx.modelNameSnapshot,
                ctx.threadID,
                ctx.turnID,
                responseMetrics
            )
        }

        if response.toolCalls.isEmpty {
            await MainActor.run {
                callbacks.endStreamingSession()
            }
        }

        return AssistantPersistenceResult(
            message: assistantMessage,
            persistedMessageID: persistedAssistantMessageID,
            hasRenderableContent: hasRenderableContent,
            completionPreview: completionPreview
        )
    }

    static func applyAssistantPersistenceFollowUp(
        _ persistenceResult: AssistantPersistenceResult,
        responseHasToolCalls: Bool,
        history: [Message],
        context ctx: SessionContext,
        callbacks: SessionCallbacks
    ) async -> [Message] {
        guard let assistantMessage = persistenceResult.message else {
            return history
        }

        var updatedHistory = history
        updatedHistory.append(assistantMessage)

        if ctx.triggeredByUserSend,
           !responseHasToolCalls,
           let target = ctx.chatNamingTarget {
            await callbacks.maybeAutoRename(
                target.provider,
                target.modelID,
                updatedHistory,
                assistantMessage
            )
        }

        return updatedHistory
    }
}
