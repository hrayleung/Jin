import Foundation

extension VertexAIAdapter {
    func decodeGenerateContentResponse(from data: Data) throws -> VertexGenerateContentResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VertexGenerateContentResponse.self, from: data)
    }

    func makeNonStreamingEventStream(
        response: VertexGenerateContentResponse
    ) throws -> AsyncThrowingStream<StreamEvent, Error> {
        if isResponseContentFiltered(response) {
            throw LLMError.contentFiltered
        }

        return AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(id: UUID().uuidString))

            let usage = usageFromVertexResponse(response)
            var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()
            for event in eventsFromVertexResponse(response, codeExecutionState: &codeExecutionState) {
                continuation.yield(event)
            }

            continuation.yield(.messageEnd(usage: usage))
            continuation.finish()
        }
    }

    func makeEventStream(
        from lineStream: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let messageID = UUID().uuidString
                do {
                    var didStart = false
                    var decodedChunkCount = 0
                    var pendingJSON = ""
                    var pendingUsage: Usage?
                    var codeExecutionState = GeminiModelConstants.GoogleCodeExecutionEventState()

                    for try await line in lineStream {
                        guard let data = normalizeVertexStreamLine(line) else { continue }

                        if !didStart {
                            didStart = true
                            continuation.yield(.messageStart(id: messageID))
                        }

                        pendingJSON += data
                        pendingJSON += "\n"
                        let outcome = try yieldParsedEvents(
                            from: &pendingJSON,
                            pendingUsage: &pendingUsage,
                            codeExecutionState: &codeExecutionState,
                            continuation: continuation
                        )
                        decodedChunkCount += outcome.decodedObjectCount

                        if outcome.contentFiltered {
                            continuation.yield(.error(.contentFiltered))
                            continuation.finish()
                            return
                        }

                        if pendingJSON.count > 64_000_000 {
                            pendingJSON = String(pendingJSON.suffix(1_048_576))
                        }
                    }

                    let finalOutcome = try yieldParsedEvents(
                        from: &pendingJSON,
                        pendingUsage: &pendingUsage,
                        codeExecutionState: &codeExecutionState,
                        continuation: continuation
                    )
                    decodedChunkCount += finalOutcome.decodedObjectCount

                    if finalOutcome.contentFiltered {
                        if !didStart {
                            continuation.yield(.messageStart(id: messageID))
                        }
                        continuation.yield(.error(.contentFiltered))
                        continuation.finish()
                        return
                    }

                    if decodedChunkCount == 0 {
                        if !didStart {
                            continuation.yield(.messageStart(id: messageID))
                        }
                        continuation.yield(.error(.decodingError(message: "Vertex AI returned an empty response with no usable JSON content.")))
                        continuation.yield(.messageEnd(usage: nil))
                        continuation.finish()
                        return
                    }

                    continuation.yield(.messageEnd(usage: pendingUsage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func yieldParsedEvents(
        from pendingJSON: inout String,
        pendingUsage: inout Usage?,
        codeExecutionState: inout GeminiModelConstants.GoogleCodeExecutionEventState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) throws -> (decodedObjectCount: Int, contentFiltered: Bool) {
        guard !pendingJSON.isEmpty else { return (0, false) }

        let jsonObjects = extractJSONObjectStrings(from: &pendingJSON)
        guard !jsonObjects.isEmpty else { return (0, false) }

        for jsonObject in jsonObjects {
            let parsed = try parseStreamChunk(jsonObject, codeExecutionState: &codeExecutionState)
            if parsed.contentFiltered {
                return (1, true)
            }
            if let usage = parsed.usage {
                pendingUsage = usage
            }
            for streamEvent in parsed.events {
                continuation.yield(streamEvent)
            }
        }

        return (jsonObjects.count, false)
    }
}
