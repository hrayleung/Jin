import Foundation

extension VertexAIAdapter {

    // MARK: - Content Translation

    func translateMessage(_ message: Message, supportsNativePDF: Bool) throws -> [String: Any] {
        try VertexAIMessageTranslation.translateMessage(message, supportsNativePDF: supportsNativePDF)
    }

    // MARK: - Stream Parsing

    func normalizeVertexStreamLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("event:") {
            return nil
        }

        if trimmed.hasPrefix(":") {
            return nil
        }

        if trimmed.hasPrefix("data:") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 5)
            let data = trimmed[start...].trimmingCharacters(in: .whitespacesAndNewlines)
            return data.isEmpty ? nil : String(data)
        }

        return trimmed
    }

    func parseStreamChunk(
        _ data: String,
        codeExecutionState: inout GeminiModelConstants.GoogleCodeExecutionEventState
    ) throws -> (events: [StreamEvent], usage: Usage?, contentFiltered: Bool) {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else {
            return ([], nil, false)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if trimmed.hasPrefix("[") {
            let responses = try decoder.decode([VertexGenerateContentResponse].self, from: jsonData)
            return responsesFromStreamChunk(
                responses,
                codeExecutionState: &codeExecutionState
            )
        }

        let response = try decoder.decode(VertexGenerateContentResponse.self, from: jsonData)
        return responsesFromStreamChunk(
            [response],
            codeExecutionState: &codeExecutionState
        )
    }

    private func responsesFromStreamChunk(
        _ responses: [VertexGenerateContentResponse],
        codeExecutionState: inout GeminiModelConstants.GoogleCodeExecutionEventState
    ) -> (events: [StreamEvent], usage: Usage?, contentFiltered: Bool) {
        if responses.contains(where: isResponseContentFiltered) {
            return ([], nil, true)
        }

        var events: [StreamEvent] = []
        var usage: Usage?
        for response in responses {
            events.append(contentsOf: eventsFromVertexResponse(response, codeExecutionState: &codeExecutionState))
            if let parsedUsage = usageFromVertexResponse(response) {
                usage = parsedUsage
            }
        }
        return (events, usage, false)
    }

    func extractJSONObjectStrings(from buffer: inout String) -> [String] {
        var results: [String] = []
        var braceDepth = 0
        var isInString = false
        var isEscaping = false
        var objectStart: String.Index?
        var lastConsumedEnd: String.Index?

        var index = buffer.startIndex
        while index < buffer.endIndex {
            let ch = buffer[index]

            if isInString {
                if isEscaping {
                    isEscaping = false
                } else if ch == "\\" {
                    isEscaping = true
                } else if ch == "\"" {
                    isInString = false
                }
            } else {
                if ch == "\"" {
                    isInString = true
                } else if ch == "{" {
                    if braceDepth == 0 {
                        objectStart = index
                    }
                    braceDepth += 1
                } else if ch == "}" {
                    if braceDepth > 0 {
                        braceDepth -= 1
                        if braceDepth == 0, let start = objectStart {
                            let end = buffer.index(after: index)
                            results.append(String(buffer[start..<end]))
                            lastConsumedEnd = end
                            objectStart = nil
                        }
                    }
                }
            }

            index = buffer.index(after: index)
        }

        if let end = lastConsumedEnd {
            buffer.removeSubrange(buffer.startIndex..<end)
        }

        while let first = buffer.first,
              first.isWhitespace || first == "," || first == "[" || first == "]" {
            buffer.removeFirst()
        }

        return results
    }

    // MARK: - Response Event Parsing

    func eventsFromVertexResponse(
        _ response: VertexGenerateContentResponse,
        codeExecutionState: inout GeminiModelConstants.GoogleCodeExecutionEventState
    ) -> [StreamEvent] {
        var events: [StreamEvent] = []

        if let candidate = response.candidates?.first,
           let content = candidate.content {
            events.append(contentsOf: GeminiModelConstants.events(
                from: content.parts ?? [],
                codeExecutionState: &codeExecutionState
            ))
        }

        let grounding = response.candidates?.first?.groundingMetadata ?? response.groundingMetadata
        events.append(contentsOf: searchActivities(from: grounding))

        return events
    }

    func searchActivities(from grounding: VertexGenerateContentResponse.GroundingMetadata?) -> [StreamEvent] {
        GoogleGroundingSearchActivities.events(
            from: grounding.map(toSharedGrounding),
            searchPrefix: "vertex-search",
            openPrefix: "vertex-open",
            searchURLPrefix: "vertex-search-url"
        )
    }

    func isResponseContentFiltered(_ response: VertexGenerateContentResponse) -> Bool {
        if response.promptFeedback?.blockReason != nil {
            return true
        }
        return response.candidates?.contains(where: isCandidateContentFiltered) == true
    }

    func isCandidateContentFiltered(_ candidate: VertexGenerateContentResponse.Candidate) -> Bool {
        let reason = (candidate.finishReason ?? "").uppercased()
        return reason == "SAFETY" || reason == "BLOCKED" || reason == "PROHIBITED_CONTENT"
    }

    private func toSharedGrounding(_ g: VertexGenerateContentResponse.GroundingMetadata) -> GoogleGroundingSearchActivities.GroundingMetadata {
        GeminiModelConstants.toSharedGrounding(g)
    }

    func usageFromVertexResponse(_ response: VertexGenerateContentResponse) -> Usage? {
        guard let usageMetadata = response.usageMetadata else { return nil }
        guard let input = usageMetadata.promptTokenCount,
              let output = usageMetadata.candidatesTokenCount else {
            return nil
        }

        return Usage(
            inputTokens: input,
            outputTokens: output,
            thinkingTokens: nil,
            cachedTokens: usageMetadata.cachedContentTokenCount
        )
    }

}
