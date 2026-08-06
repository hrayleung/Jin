import Foundation

extension MetaAdapter {
    func parseSSEEvent(
        type: String,
        data: String,
        functionCallsByItemID: inout [String: ResponsesAPIFunctionCallState],
        emittedEncryptedReasoningIDs: inout Set<String>
    ) throws -> [StreamEvent] {
        guard let jsonData = data.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder.snakeCaseConverting()

        switch type {
        case "response.created":
            let event = try decoder.decode(ResponsesAPICreatedEvent.self, from: jsonData)
            return [.messageStart(id: event.response.id)]

        case "response.output_text.delta":
            let event = try decoder.decode(ResponsesAPIOutputTextDeltaEvent.self, from: jsonData)
            return [.contentDelta(.text(event.delta))]

        case "response.reasoning_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningTextDeltaEvent.self, from: jsonData)
            return [.thinkingDelta(.thinking(textDelta: event.delta, signature: nil))]

        case "response.reasoning_summary_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningSummaryTextDeltaEvent.self, from: jsonData)
            return [.thinkingDelta(.thinking(textDelta: event.delta, signature: nil))]

        case "response.output_item.added":
            let event = try decoder.decode(ResponsesAPIOutputItemAddedEvent.self, from: jsonData)
            if event.item.type == "function_call" {
                guard let itemID = event.item.id,
                      let callID = event.item.callId,
                      let name = event.item.name else {
                    return []
                }
                functionCallsByItemID[itemID] = ResponsesAPIFunctionCallState(callID: callID, name: name)
                return [.toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))]
            }

            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                event.item,
                outputIndex: event.outputIndex,
                sequenceNumber: event.sequenceNumber
               ) {
                return [.searchActivity(activity)]
            }
            return []

        case "response.output_item.done":
            let event = try decoder.decode(ResponsesAPIOutputItemDoneEvent.self, from: jsonData)
            var events: [StreamEvent] = []

            if event.item.type == "reasoning" {
                events.append(contentsOf: reasoningStreamEvents(
                    from: event.item,
                    emittedEncryptedReasoningIDs: &emittedEncryptedReasoningIDs
                ))
            }

            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                event.item,
                outputIndex: event.outputIndex,
                sequenceNumber: event.sequenceNumber
               ) {
                events.append(.searchActivity(activity))
            }

            if event.item.type == "message",
               let activity = citationSearchActivityFromMessageItem(
                event.item,
                outputIndex: event.outputIndex,
                sequenceNumber: event.sequenceNumber
               ) {
                events.append(.searchActivity(activity))
            }

            return events

        case "response.function_call_arguments.delta":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDeltaEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return [] }
            functionCallsByItemID[event.itemId]?.argumentsBuffer += event.delta
            return [.toolCallDelta(id: state.callID, argumentsDelta: event.delta)]

        case "response.function_call_arguments.done":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDoneEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return [] }
            functionCallsByItemID.removeValue(forKey: event.itemId)
            let args = parseJSONObject(event.arguments)
            return [.toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args))]

        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed",
             "response.web_search_call.failed":
            let event = try decoder.decode(ResponsesAPIWebSearchCallStatusEvent.self, from: jsonData)
            return [
                .searchActivity(
                    SearchActivity(
                        id: event.itemId,
                        type: "web_search_call",
                        status: searchStatus(fromEventType: type),
                        arguments: [:],
                        outputIndex: event.outputIndex,
                        sequenceNumber: event.sequenceNumber
                    )
                )
            ]

        case "response.completed":
            let event = try decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData)
            var events: [StreamEvent] = []
            // Safety net: emit any encrypted reasoning that arrived only on the
            // completed payload (some streams may omit it on output_item.done).
            if let output = event.response.output {
                for item in output where item.type == "reasoning" {
                    events.append(contentsOf: reasoningStreamEvents(
                        from: item,
                        emittedEncryptedReasoningIDs: &emittedEncryptedReasoningIDs
                    ))
                }
            }
            events.append(.messageEnd(usage: event.response.toUsage()))
            return events

        case "response.failed":
            if let errorEvent = try? decoder.decode(ResponsesAPIFailedEvent.self, from: jsonData),
               let message = errorEvent.response.error?.message {
                return [
                    .error(.providerError(
                        code: errorEvent.response.error?.code ?? "response_failed",
                        message: message
                    ))
                ]
            }
            return [.error(.providerError(code: "response_failed", message: data))]

        default:
            return []
        }
    }

    /// Capture Meta encrypted CoT for persistence / later input replay.
    func reasoningStreamEvents(
        from item: ResponsesAPIOutputItemAddedEvent.Item,
        emittedEncryptedReasoningIDs: inout Set<String>
    ) -> [StreamEvent] {
        var events: [StreamEvent] = []

        // Prefer summary text when the stream did not already emit reasoning deltas
        // for this item; empty summary is normal.
        if let summaryTexts = item.summary?
            .compactMap({ $0.type == "summary_text" ? $0.text : nil })
            .filter({ !$0.isEmpty }),
           !summaryTexts.isEmpty {
            // Only useful if we want summary in the UI; text deltas usually cover this.
            // Skip to avoid duplicate UI noise when deltas already streamed.
            _ = summaryTexts
        }

        guard let encrypted = item.encryptedContent?.trimmedNonEmpty else {
            return events
        }

        let dedupeKey = item.id ?? encrypted
        guard emittedEncryptedReasoningIDs.insert(dedupeKey).inserted else {
            return events
        }

        events.append(.thinkingDelta(.redacted(data: encrypted, id: item.id)))
        return events
    }

    func reasoningStreamEvents(
        from item: ResponsesAPIOutputItem,
        emittedEncryptedReasoningIDs: inout Set<String>
    ) -> [StreamEvent] {
        // Adapt OutputItem → Item-shaped handling
        guard let encrypted = item.encryptedContent?.trimmedNonEmpty else {
            return []
        }
        let dedupeKey = item.id ?? encrypted
        guard emittedEncryptedReasoningIDs.insert(dedupeKey).inserted else {
            return []
        }
        return [.thinkingDelta(.redacted(data: encrypted, id: item.id))]
    }

    func searchActivityFromOutputItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        guard let id = item.id else { return nil }
        let actionType = item.action?.type ?? "web_search_call"
        return SearchActivity(
            id: id,
            type: actionType,
            status: searchStatus(from: item.status),
            arguments: ResponsesAPIResponse.searchActivityArguments(from: item.action),
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    func citationSearchActivityFromMessageItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        outputIndex: Int?,
        sequenceNumber: Int?
    ) -> SearchActivity? {
        let arguments = ResponsesAPIResponse.citationArguments(from: item.content)
        guard !arguments.isEmpty else { return nil }

        let baseID = item.id ?? "message_\(outputIndex ?? -1)"
        return SearchActivity(
            id: "\(baseID):citations",
            type: "url_citation",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: sequenceNumber
        )
    }

    func searchStatus(from raw: String?) -> SearchActivityStatus {
        guard let raw, !raw.isEmpty else { return .inProgress }
        return SearchActivityStatus(rawValue: raw)
    }

    func searchStatus(fromEventType eventType: String) -> SearchActivityStatus {
        if eventType.hasSuffix(".completed") {
            return .completed
        }
        if eventType.hasSuffix(".searching") {
            return .searching
        }
        if eventType.hasSuffix(".failed") {
            return .failed
        }
        return .inProgress
    }
}
