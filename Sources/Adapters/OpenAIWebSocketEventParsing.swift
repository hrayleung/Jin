import Foundation

extension OpenAIWebSocketAdapter {

    // MARK: - Event Type Parsing

    func parseEventType(from jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = object["type"] as? String,
              !type.isEmpty else {
            return nil
        }
        return type
    }

    func isTerminalResponseEventType(_ eventType: String) -> Bool {
        eventType == "response.completed"
            || eventType == "response.failed"
            || eventType == "response.incomplete"
            || eventType == "response.canceled"
            || eventType == "response.cancelled"
            || eventType == "error"
    }

    // MARK: - SSE Event Parsing

    func parseSSEEvent(
        type: String,
        data: String,
        functionCallsByItemID: inout [String: ResponsesAPIFunctionCallState]
    ) throws -> StreamEvent? {
        guard let jsonData = data.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        switch type {
        case "response.created":
            let event = try decoder.decode(ResponsesAPICreatedEvent.self, from: jsonData)
            return .messageStart(id: event.response.id)
        case "error":
            return .error(Self.decodeErrorEventPayload(jsonData, fallbackMessage: data))

        case "response.output_text.delta":
            let event = try decoder.decode(ResponsesAPIOutputTextDeltaEvent.self, from: jsonData)
            return .contentDelta(.text(event.delta))

        case "response.reasoning_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.reasoning_summary_text.delta":
            let event = try decoder.decode(ResponsesAPIReasoningSummaryTextDeltaEvent.self, from: jsonData)
            return .thinkingDelta(.thinking(textDelta: event.delta, signature: nil))

        case "response.output_item.added":
            let event = try decoder.decode(ResponsesAPIOutputItemAddedEvent.self, from: jsonData)
            if event.item.type == "function_call" {
                guard let itemID = event.item.id,
                      let callID = event.item.callId,
                      let name = event.item.name else {
                    return nil
                }

                functionCallsByItemID[itemID] = ResponsesAPIFunctionCallState(callID: callID, name: name)
                return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))
            }

            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                    event.item,
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            return nil

        case "response.output_item.done":
            let event = try decoder.decode(ResponsesAPIOutputItemDoneEvent.self, from: jsonData)
            if event.item.type == "web_search_call",
               let activity = searchActivityFromOutputItem(
                    event.item,
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            if event.item.type == "message",
               let activity = citationSearchActivityFromMessageItem(
                    event.item,
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
               ) {
                return .searchActivity(activity)
            }
            return nil

        case "response.function_call_arguments.delta":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDeltaEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }

            functionCallsByItemID[event.itemId]?.argumentsBuffer += event.delta
            return .toolCallDelta(id: state.callID, argumentsDelta: event.delta)

        case "response.function_call_arguments.done":
            let event = try decoder.decode(ResponsesAPIFunctionCallArgumentsDoneEvent.self, from: jsonData)
            guard let state = functionCallsByItemID[event.itemId] else { return nil }
            functionCallsByItemID.removeValue(forKey: event.itemId)

            let args = parseJSONObject(event.arguments)
            return .toolCallEnd(ToolCall(id: state.callID, name: state.name, arguments: args))

        case "response.web_search_call.in_progress",
             "response.web_search_call.searching",
             "response.web_search_call.completed",
             "response.web_search_call.failed":
            let event = try decoder.decode(ResponsesAPIWebSearchCallStatusEvent.self, from: jsonData)
            return .searchActivity(
                SearchActivity(
                    id: event.itemId,
                    type: "web_search_call",
                    status: searchStatus(fromEventType: type),
                    arguments: [:],
                    outputIndex: event.outputIndex,
                    sequenceNumber: event.sequenceNumber
                )
            )

        case "response.completed":
            let event = try decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData)
            return .messageEnd(usage: event.response.toUsage())

        case "response.failed":
            if let errorEvent = try? decoder.decode(ResponsesAPIFailedEvent.self, from: jsonData),
               let message = errorEvent.response.error?.message {
                return .error(.providerError(code: errorEvent.response.error?.code ?? "response_failed", message: message))
            }
            return .error(.providerError(code: "response_failed", message: data))

        default:
            return nil
        }
    }

    // MARK: - Search Activity Helpers

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
