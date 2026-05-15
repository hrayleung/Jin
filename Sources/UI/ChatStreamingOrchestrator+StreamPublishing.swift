import Foundation

extension ChatStreamingOrchestrator {
    static func applyStreamContentPart(
        _ part: ContentPart,
        accumulator: inout StreamingResponseAccumulator,
        uiFlushBuffer: inout StreamingUIFlushBuffer,
        diagnostics: inout StreamingLoopDiagnosticState,
        context ctx: SessionContext
    ) {
        switch part {
        case .text(let delta):
            if let deltaCount = diagnostics.firstContentDeltaCount(delta) {
                logFirstContentDelta(count: deltaCount, context: ctx)
            }
            accumulator.appendTextDelta(delta)
            uiFlushBuffer.appendText(delta)
        case .image(let image):
            accumulator.appendImage(image)
        case .video(let video):
            accumulator.appendVideo(video)
        case .quote, .file, .audio, .thinking, .redactedThinking:
            break
        }
    }

    static func applyStreamThinkingDelta(
        _ delta: ThinkingDelta,
        accumulator: inout StreamingResponseAccumulator,
        uiFlushBuffer: inout StreamingUIFlushBuffer,
        diagnostics: inout StreamingLoopDiagnosticState,
        context ctx: SessionContext
    ) {
        accumulator.appendThinkingDelta(delta)

        switch delta {
        case .thinking(let textDelta, _):
            guard !textDelta.isEmpty else { return }
            if let deltaCount = diagnostics.firstThinkingDeltaCount(textDelta) {
                logFirstThinkingDelta(count: deltaCount, context: ctx)
            }
            uiFlushBuffer.appendThinking(textDelta)
        case .redacted:
            break
        }
    }

    static func applyStreamingUIFlush(
        _ flush: StreamingUIFlush,
        streamingState: StreamingMessageState,
        context ctx: SessionContext
    ) async {
        if flush.isFirstFlush {
            // #region agent log
            ChatDiagnosticLogger.log(
                runId: ctx.diagnosticRunID,
                hypothesisId: "H6",
                message: "chat_first_ui_flush",
                data: firstUIFlushDiagnosticData(for: flush, context: ctx)
            )
            // #endregion
        }

        let deltaDiagnosticData = uiFlushDeltaDiagnosticData(for: flush, context: ctx)
        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H8",
            message: "chat_ui_flush_mainactor_start",
            data: deltaDiagnosticData
        )
        // #endregion

        await MainActor.run {
            streamingState.appendDeltas(
                textDelta: flush.textDelta,
                thinkingDelta: flush.thinkingDelta
            )
        }

        // #region agent log
        ChatDiagnosticLogger.log(
            runId: ctx.diagnosticRunID,
            hypothesisId: "H8",
            message: "chat_ui_flush_mainactor_end",
            data: deltaDiagnosticData
        )
        // #endregion
    }

    static func flushStreamingUIIfNeeded(
        buffer: inout StreamingUIFlushBuffer,
        force: Bool = false,
        now: TimeInterval,
        streamingState: StreamingMessageState,
        context ctx: SessionContext
    ) async {
        guard let flush = buffer.flushIfNeeded(force: force, now: now) else { return }

        await applyStreamingUIFlush(
            flush,
            streamingState: streamingState,
            context: ctx
        )
    }

    static func applyStreamToolCall(
        _ call: ToolCall,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState
    ) async {
        accumulator.upsertToolCall(call)
        let visibleToolCalls = accumulator.buildToolCalls()
        await MainActor.run {
            streamingState.setToolCalls(visibleToolCalls)
        }
    }

    static func applyStreamSearchActivity(
        _ activity: SearchActivity,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState
    ) async {
        accumulator.upsertSearchActivity(activity)
        await MainActor.run {
            streamingState.upsertSearchActivity(activity)
        }
    }

    static func applyStreamCodeExecutionActivity(
        _ activity: CodeExecutionActivity,
        accumulator: inout StreamingResponseAccumulator,
        streamingState: StreamingMessageState
    ) async {
        accumulator.upsertCodeExecutionActivity(activity)
        await MainActor.run {
            streamingState.upsertCodeExecutionActivity(activity)
        }
    }
}
