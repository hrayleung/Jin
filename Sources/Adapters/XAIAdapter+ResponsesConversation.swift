import Foundation

extension XAIAdapter {
    func sendResponsesConversation(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try buildResponsesRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let response = try decoder.decode(ResponsesAPIResponse.self, from: data)

            return makeNonStreamingResponseStream(response)
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        let streamDecoder = JSONDecoder()
        streamDecoder.keyDecodingStrategy = .convertFromSnakeCase

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    var codeInterpreterState = OpenAICodeInterpreterState()
                    var streamedOutputText = ""
                    var didEmitTerminalMessageEnd = false

                    for try await event in sseStream {
                        switch event {
                        case .event(let type, let data):
                            if emitIncompleteEventIfNeeded(
                                type: type,
                                data: data,
                                decoder: streamDecoder,
                                continuation: continuation,
                                didEmitTerminalMessageEnd: &didEmitTerminalMessageEnd
                            ) {
                                continue
                            }

                            emitCitationActivityIfNeeded(
                                type: type,
                                data: data,
                                decoder: streamDecoder,
                                fallbackText: streamedOutputText,
                                continuation: continuation
                            )

                            if let streamEvent = try parseSSEEvent(
                                type: type,
                                data: data,
                                functionCallsByItemID: &functionCallsByItemID,
                                codeInterpreterState: &codeInterpreterState
                            ) {
                                if case .contentDelta(.text(let delta)) = streamEvent {
                                    streamedOutputText.append(delta)
                                }
                                if case .messageEnd = streamEvent {
                                    didEmitTerminalMessageEnd = true
                                }
                                continuation.yield(streamEvent)
                            }
                        case .done:
                            if !didEmitTerminalMessageEnd {
                                continuation.yield(.messageEnd(usage: nil))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildResponsesRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let nativePDFEnabled = allowNativePDF && XAIModelSupport.supportsNativePDF(modelID)
        let supportsFunctionTools = XAIResponsesRequestSupport.supportsClientFunctionTools(modelID: modelID)
        let functionTools = supportsFunctionTools ? (translateTools(tools) as? [[String: Any]] ?? []) : []
        let body = XAIResponsesRequestSupport.responsesBody(
            modelID: modelID,
            input: try translateInput(messages, supportsNativePDF: nativePDFEnabled),
            streaming: streaming,
            controls: controls,
            functionTools: functionTools,
            supportsWebSearch: modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID),
            supportsClientFunctionTools: supportsFunctionTools
        )

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/responses"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            additionalHeaders: XAIResponsesRequestSupport.additionalHeaders(controls: controls),
            includeUserAgent: false
        )
    }

    private func makeNonStreamingResponseStream(
        _ response: ResponsesAPIResponse
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(id: response.id))

            for text in response.outputTextParts {
                continuation.yield(.contentDelta(.text(text)))
            }

            let outputText = response.outputTextParts.joined(separator: "\n")
            if let citationActivity = citationSearchActivity(
                sources: citationCandidates(
                    citations: response.citations,
                    output: response.output,
                    fallbackText: outputText
                ),
                responseID: response.id
            ) {
                continuation.yield(.searchActivity(citationActivity))
            }

            if let notice = response.incompleteNoticeMarkdown {
                continuation.yield(.contentDelta(.text(notice)))
            }

            continuation.yield(.messageEnd(usage: response.toUsage()))
            continuation.finish()
        }
    }

    private func emitIncompleteEventIfNeeded(
        type: String,
        data: String,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        didEmitTerminalMessageEnd: inout Bool
    ) -> Bool {
        guard type == "response.incomplete",
              let jsonData = data.data(using: .utf8),
              let incomplete = try? decoder.decode(ResponsesAPIIncompleteEvent.self, from: jsonData) else {
            return false
        }

        if let notice = incomplete.response.incompleteNoticeMarkdown {
            continuation.yield(.contentDelta(.text(notice)))
        }
        continuation.yield(.messageEnd(usage: incomplete.response.toUsage()))
        didEmitTerminalMessageEnd = true
        return true
    }

    private func emitCitationActivityIfNeeded(
        type: String,
        data: String,
        decoder: JSONDecoder,
        fallbackText: String,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        guard type == "response.completed",
              let jsonData = data.data(using: .utf8),
              let completed = try? decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData),
              let citationActivity = citationSearchActivity(
                  sources: citationCandidates(
                      citations: completed.response.citations,
                      output: completed.response.output,
                      fallbackText: fallbackText
                  ),
                  responseID: completed.response.id
              ) else {
            return
        }

        continuation.yield(.searchActivity(citationActivity))
    }
}
