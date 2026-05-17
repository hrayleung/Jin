import Foundation

extension ChatStreamingOrchestrator {
    static func baseStreamDiagnosticData(
        context ctx: SessionContext
    ) -> [String: String] {
        [
            "conversationID": ctx.conversationID.uuidString
        ]
    }

    static func adapterStreamCreatedDiagnosticData(
        providerType: ProviderType,
        modelID: String,
        historyCount: Int,
        toolCount: Int,
        durationMs: Int,
        context ctx: SessionContext
    ) -> [String: String] {
        var data = baseStreamDiagnosticData(context: ctx)
        data["providerType"] = String(describing: providerType)
        data["modelID"] = modelID
        data["historyCount"] = String(historyCount)
        data["toolCount"] = String(toolCount)
        data["durationMs"] = String(durationMs)
        return data
    }

    static func firstStreamEventDiagnosticData(
        eventName: String,
        context ctx: SessionContext
    ) -> [String: String] {
        var data = baseStreamDiagnosticData(context: ctx)
        data["event"] = eventName
        return data
    }

    static func firstContentDeltaDiagnosticData(
        deltaCount: Int,
        context ctx: SessionContext
    ) -> [String: String] {
        var data = baseStreamDiagnosticData(context: ctx)
        data["textDeltaCount"] = String(deltaCount)
        return data
    }

    static func firstThinkingDeltaDiagnosticData(
        deltaCount: Int,
        context ctx: SessionContext
    ) -> [String: String] {
        var data = baseStreamDiagnosticData(context: ctx)
        data["thinkingDeltaCount"] = String(deltaCount)
        return data
    }

    static func firstUIFlushDiagnosticData(
        for flush: StreamingUIFlush,
        context ctx: SessionContext
    ) -> [String: String] {
        var data = baseStreamDiagnosticData(context: ctx)
        data["force"] = String(flush.force)
        data["textDeltaCount"] = String(flush.textDelta.count)
        data["thinkingDeltaCount"] = String(flush.thinkingDelta.count)
        return data
    }

    static func uiFlushDeltaDiagnosticData(
        for flush: StreamingUIFlush,
        context ctx: SessionContext
    ) -> [String: String] {
        var data = baseStreamDiagnosticData(context: ctx)
        data["textDeltaCount"] = String(flush.textDelta.count)
        data["thinkingDeltaCount"] = String(flush.thinkingDelta.count)
        return data
    }

    static func logAdapterStreamCreated(
        providerType: ProviderType,
        modelID: String,
        historyCount: Int,
        toolCount: Int,
        durationMs: Int,
        context ctx: SessionContext
    ) {
        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H3",
            message: "chat_adapter_stream_created",
            data: adapterStreamCreatedDiagnosticData(
                providerType: providerType,
                modelID: modelID,
                historyCount: historyCount,
                toolCount: toolCount,
                durationMs: durationMs,
                context: ctx
            )
        )
        // #endregion
    }

    static func logFirstStreamEvent(
        _ eventName: String,
        context ctx: SessionContext
    ) {
        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H5",
            message: "chat_first_stream_event",
            data: firstStreamEventDiagnosticData(eventName: eventName, context: ctx)
        )
        // #endregion
    }

    static func logFirstContentDelta(
        count deltaCount: Int,
        context ctx: SessionContext
    ) {
        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H7",
            message: "chat_first_content_delta",
            data: firstContentDeltaDiagnosticData(deltaCount: deltaCount, context: ctx)
        )
        // #endregion
    }

    static func logFirstThinkingDelta(
        count deltaCount: Int,
        context ctx: SessionContext
    ) {
        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H7",
            message: "chat_first_thinking_delta",
            data: firstThinkingDeltaDiagnosticData(deltaCount: deltaCount, context: ctx)
        )
        // #endregion
    }

    static func observeStreamEvent(
        _ event: StreamEvent,
        at date: Date,
        metricsCollector: inout StreamingResponseMetricsCollector,
        diagnostics: inout StreamingLoopDiagnosticState,
        context ctx: SessionContext
    ) {
        metricsCollector.observe(event: event, at: date)

        if let firstEventName = diagnostics.firstStreamEventName(event) {
            logFirstStreamEvent(firstEventName, context: ctx)
        }
    }
}
