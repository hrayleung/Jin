import Foundation

actor AnthropicAdapter: LLMProviderAdapter {
    let providerConfig: ProviderConfig
    let capabilities: ModelCapability = [.streaming, .toolCalling, .vision, .reasoning, .promptCaching]

    let networkManager: NetworkManager
    let apiKey: String

    init(providerConfig: ProviderConfig, apiKey: String, networkManager: NetworkManager = NetworkManager()) {
        self.providerConfig = providerConfig
        self.apiKey = apiKey
        self.networkManager = networkManager
    }

    func sendMessage(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let prepared = try await buildRequestBody(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )
        let initialRequest = try makeMessagesRequest(body: prepared.body, betaHeader: prepared.betaHeader)

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    var request = initialRequest
                    var pausedContent: [[String: Any]] = []
                    var pauseTurnContinuations = 0
                    var containerID: String?
                    var usageAccumulator = AnthropicUsageAccumulator()

                    while true {
                        var response = StreamedResponse()
                        do {
                            try await streamResponse(
                                request,
                                into: &response,
                                blockIndexOffset: pausedContent.count,
                                usageAccumulator: &usageAccumulator,
                                continuation: continuation
                            )
                        } catch {
                            guard !Task.isCancelled,
                                  let notice = AnthropicStopReasonSupport.resumeFailureNoticeMarkdown(
                                      for: error,
                                      pauseTurnContinuations: pauseTurnContinuations,
                                      failedResponseStartedToolCall: response.startedToolCall
                                  ) else {
                                throw error
                            }
                            continuation.yield(.contentDelta(.text(notice)))
                            continuation.yield(.messageEnd(usage: usageAccumulator.toUsage()))
                            break
                        }
                        containerID = response.recorder.containerID ?? containerID

                        // The server-tool loop hit its per-request iteration cap mid-turn. Resume by
                        // re-sending everything the turn produced so far; the reply keeps streaming
                        // into the same message.
                        if response.recorder.stopReason == AnthropicStopReasonSupport.pauseTurn,
                           !response.recorder.content.isEmpty,
                           pauseTurnContinuations < AnthropicStopReasonSupport.maxPauseTurnContinuations {
                            try Task.checkCancellation()
                            pausedContent.append(contentsOf: response.recorder.content)
                            pauseTurnContinuations += 1
                            request = try makeMessagesRequest(
                                body: AnthropicStopReasonSupport.continuationBody(
                                    from: prepared.body,
                                    pausedContent: pausedContent,
                                    containerID: containerID
                                ),
                                betaHeader: prepared.betaHeader
                            )
                            usageAccumulator.beginNextResponse()
                            continue
                        }

                        if let notice = AnthropicStopReasonSupport.noticeMarkdown(
                            for: response.recorder.stopReason,
                            pauseTurnContinuations: pauseTurnContinuations
                        ) {
                            continuation.yield(.contentDelta(.text(notice)))
                        }
                        if response.deferredMessageEnd {
                            continuation.yield(.messageEnd(usage: usageAccumulator.toUsage()))
                        }
                        break
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // When the consumer stops iterating (Stop, conversation delete),
            // cancel the producer — otherwise it keeps draining the SSE
            // stream and the HTTP transfer runs to completion.
            continuation.onTermination = { _ in producerTask.cancel() }
        }
    }

    func translateTools(_ tools: [ToolDefinition]) -> Any {
        AnthropicToolSpecSupport.customToolSpecs(from: tools)
    }

    private struct StreamedResponse {
        var recorder = AnthropicStreamedResponseRecorder()
        /// A `messageEnd` held back because the stop reason still needs handling — the turn is
        /// resumed, or a notice has to land before the reply is marked finished.
        var deferredMessageEnd = false
        /// The orchestrator runs every tool call it has seen, so a response that fails after
        /// starting one must not end as if it had finished.
        var startedToolCall = false
    }

    /// Streams one HTTP response of the turn into `continuation`. `response` is `inout` so what
    /// was received survives a throw; an `error` event ends the response the same way.
    private func streamResponse(
        _ request: URLRequest,
        into response: inout StreamedResponse,
        blockIndexOffset: Int,
        usageAccumulator: inout AnthropicUsageAccumulator,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let sseStream = await networkManager.streamRequest(request, parser: SSEParser())

        var currentMessageID: String?
        var currentBlockIndex: Int?
        var currentToolUse: AnthropicToolCallBuilder?
        var currentServerToolUse: AnthropicSearchActivityBuilder?
        var currentCodeExecutionID: String?
        var currentCodeExecutionCode: String = ""
        var currentContentBlockType: String?
        var currentThinkingSignature: String?

        for try await event in sseStream {
            let streamEvent: StreamEvent?
            switch event {
            case .event(_, let data):
                response.recorder.record(data)
                do {
                    streamEvent = try parseJSONLine(
                        data,
                        currentMessageID: &currentMessageID,
                        currentBlockIndex: &currentBlockIndex,
                        currentToolUse: &currentToolUse,
                        currentServerToolUse: &currentServerToolUse,
                        currentCodeExecutionID: &currentCodeExecutionID,
                        currentCodeExecutionCode: &currentCodeExecutionCode,
                        currentContentBlockType: &currentContentBlockType,
                        currentThinkingSignature: &currentThinkingSignature,
                        usageAccumulator: &usageAccumulator,
                        blockIndexOffset: blockIndexOffset
                    )
                } catch is DecodingError {
                    // Be resilient to provider-side schema drift in individual events.
                    // Skip malformed events instead of aborting the whole response stream.
                    continue
                } catch is LLMError {
                    // Malformed tool call arguments or similar event-level issue.
                    // Skip the broken event rather than killing the entire stream.
                    continue
                }
            case .done:
                streamEvent = .messageEnd(usage: usageAccumulator.toUsage())
            }

            guard let streamEvent else { continue }
            switch streamEvent {
            case .error(let error):
                throw error
            case .messageEnd where AnthropicStopReasonSupport.defersMessageEnd(for: response.recorder.stopReason):
                response.deferredMessageEnd = true
                continue
            case .toolCallStart:
                response.startedToolCall = true
            default:
                break
            }
            continuation.yield(streamEvent)
        }
    }
}

// Stream parsing and search activities: AnthropicStreamParsing.swift
// Request construction: AnthropicAdapter+RequestSupport.swift
// Response types: AnthropicAdapterResponseTypes.swift
// Message translation: AnthropicAdapterMessageTranslation.swift
// `pause_turn` / truncation handling: AnthropicStopReasonSupport.swift
