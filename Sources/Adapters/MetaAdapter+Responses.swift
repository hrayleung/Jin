import Foundation

extension MetaAdapter {
    func sendResponsesConversation(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let request = try await buildResponsesRequest(
            messages: messages,
            modelID: modelID,
            controls: controls,
            tools: tools,
            streaming: streaming
        )

        if !streaming {
            let (data, _) = try await networkManager.sendRequest(request)
            let response = try JSONDecoder.snakeCaseConverting().decode(ResponsesAPIResponse.self, from: data)
            return makeNonStreamingResponseStream(response)
        }

        let parser = SSEParser()
        let sseStream = await networkManager.streamRequest(request, parser: parser)
        let streamDecoder = JSONDecoder.snakeCaseConverting()

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    var functionCallsByItemID: [String: ResponsesAPIFunctionCallState] = [:]
                    var emittedEncryptedReasoningIDs = Set<String>()
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

                            do {
                                let streamEvents = try parseSSEEvent(
                                    type: type,
                                    data: data,
                                    functionCallsByItemID: &functionCallsByItemID,
                                    emittedEncryptedReasoningIDs: &emittedEncryptedReasoningIDs
                                )
                                for streamEvent in streamEvents {
                                    if case .messageEnd = streamEvent {
                                        didEmitTerminalMessageEnd = true
                                    }
                                    continuation.yield(streamEvent)
                                }
                            } catch is DecodingError {
                                continue
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
            continuation.onTermination = { _ in producerTask.cancel() }
        }
    }

    func buildResponsesRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> URLRequest {
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let webSearchEnabled = controls.webSearch?.enabled == true
            && modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
        let functionTools = tools.map(MetaResponsesInputSupport.responsesToolDefinition)

        let body = MetaResponsesRequestSupport.responsesBody(
            modelID: modelID,
            input: try await translateInput(messages, allowNativePDF: allowNativePDF),
            streaming: streaming,
            controls: controls,
            functionTools: functionTools,
            webSearchEnabled: webSearchEnabled,
            providerType: providerConfig.type
        )

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/responses"),
            apiKey: apiKey,
            body: body,
            accept: nil,
            includeUserAgent: false
        )
    }

    private func makeNonStreamingResponseStream(
        _ response: ResponsesAPIResponse
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(id: response.id))

            var emittedEncryptedReasoningIDs = Set<String>()

            // Preserve output order for tool loops: reasoning → message text → tools.
            for item in response.output {
                switch item.type {
                case "reasoning":
                    for event in reasoningStreamEvents(
                        from: item,
                        emittedEncryptedReasoningIDs: &emittedEncryptedReasoningIDs
                    ) {
                        continuation.yield(event)
                    }
                    // Surface summary text for the UI when present.
                    if let summaryTexts = item.summary?
                        .compactMap({ $0.type == "summary_text" ? $0.text : nil }),
                       !summaryTexts.isEmpty {
                        for text in summaryTexts where !text.isEmpty {
                            continuation.yield(.thinkingDelta(.thinking(textDelta: text, signature: nil)))
                        }
                    }

                case "message":
                    if let texts = item.content?
                        .compactMap({ $0.type == "output_text" ? $0.text : nil }) {
                        for text in texts where !text.isEmpty {
                            continuation.yield(.contentDelta(.text(text)))
                        }
                    }
                    let citations = ResponsesAPIResponse.citationArguments(from: item.content)
                    if !citations.isEmpty {
                        let baseID = item.id ?? "message"
                        continuation.yield(.searchActivity(SearchActivity(
                            id: "\(baseID):citations",
                            type: "url_citation",
                            status: .completed,
                            arguments: citations
                        )))
                    }

                case "web_search_call":
                    if let id = item.id {
                        continuation.yield(.searchActivity(SearchActivity(
                            id: id,
                            type: item.action?.type ?? "web_search_call",
                            status: SearchActivityStatus(rawValue: item.status ?? "completed"),
                            arguments: ResponsesAPIResponse.searchActivityArguments(from: item.action)
                        )))
                    }

                case "function_call":
                    // Streaming is the primary tool-call path in Jin. Non-streaming
                    // function_call items lack full argument fields on OutputItem today;
                    // callers that need tools should use streaming=true.
                    break

                default:
                    break
                }
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
}
