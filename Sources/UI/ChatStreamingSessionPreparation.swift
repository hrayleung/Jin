import Foundation

extension ChatStreamingOrchestrator {
    static func prepareSession(from ctx: SessionContext) async throws -> PreparedSession {
        guard let providerConfig = ctx.providerConfig else {
            throw LLMError.invalidRequest(message: "Provider not found. Configure it in Settings.")
        }

        let prepareHistoryStartedAt = ProcessInfo.processInfo.systemUptime
        var history = prepareHistory(from: ctx)
        let prepareHistoryDurationMs = Int((ProcessInfo.processInfo.systemUptime - prepareHistoryStartedAt) * 1000)

        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H3",
            message: "chat_prepare_history_complete",
            data: [
                "conversationID": ctx.conversationID.uuidString,
                "threadID": ctx.threadID.uuidString,
                "snapshotCount": String(ctx.messageSnapshots.count),
                "historyCount": String(history.count),
                "shouldTruncateMessages": String(ctx.shouldTruncateMessages),
                "maxHistoryMessages": ctx.maxHistoryMessages.map(String.init) ?? "nil",
                "durationMs": String(prepareHistoryDurationMs)
            ]
        )
        // #endregion

        let providerManager = ProviderManager()
        let adapter = try await providerManager.createAdapter(for: providerConfig)
        let (mcpTools, mcpRoutes) = try await MCPHub.shared.toolDefinitions(for: ctx.mcpServerConfigs)
        let (builtinTools, builtinRoutes) = await BuiltinSearchToolHub.shared.toolDefinitions(
            for: ctx.controlsToUse,
            useBuiltinSearch: ctx.shouldOfferBuiltinSearch
        )
        let allTools = mcpTools + builtinTools

        var requestControls = ctx.controlsToUse
        let optimizedContextCache = await ContextCacheUtilities.applyAutomaticContextCacheOptimizations(
            adapter: adapter,
            providerType: providerConfig.type,
            modelID: ctx.modelID,
            messages: history,
            controls: requestControls,
            tools: allTools
        )
        history = optimizedContextCache.messages
        requestControls = optimizedContextCache.controls
        ChatControlNormalizationSupport.sanitizeProviderSpecificForProvider(
            providerConfig.type,
            controls: &requestControls
        )

        return PreparedSession(
            providerConfig: providerConfig,
            adapter: adapter,
            history: history,
            requestControls: requestControls,
            allTools: allTools,
            mcpRoutes: mcpRoutes,
            builtinRoutes: builtinRoutes,
            maxToolIterations: 8
        )
    }

}
