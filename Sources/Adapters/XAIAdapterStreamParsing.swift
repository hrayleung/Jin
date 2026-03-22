import Foundation

// MARK: - SSE Event Parsing

extension XAIAdapter {
    func parseSSEEvent(
        type: String,
        data: String,
        functionCallsByItemID: inout [String: ResponsesAPIFunctionCallState],
        codeInterpreterState: inout OpenAICodeInterpreterState
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

            if event.item.type == "code_interpreter_call",
               let itemID = event.item.id {
                codeInterpreterState.currentItemID = itemID
                codeInterpreterState.codeBuffer = ""
                return .codeExecutionActivity(CodeExecutionActivity(
                    id: itemID,
                    status: .inProgress
                ))
            }

            guard event.item.type == "function_call",
                  let itemID = event.item.id,
                  let callID = event.item.callId,
                  let name = event.item.name else {
                return nil
            }

            functionCallsByItemID[itemID] = ResponsesAPIFunctionCallState(callID: callID, name: name)
            return .toolCallStart(ToolCall(id: callID, name: name, arguments: [:]))

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

        case "response.completed":
            let event = try decoder.decode(ResponsesAPICompletedEvent.self, from: jsonData)
            return .messageEnd(usage: event.response.toUsage())

        case "response.code_interpreter_call.in_progress":
            let event = try decoder.decode(ResponsesAPICodeInterpreterStatusEvent.self, from: jsonData)
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .inProgress
            ))

        case "response.code_interpreter_call_code.delta":
            let event = try decoder.decode(ResponsesAPICodeInterpreterCodeDeltaEvent.self, from: jsonData)
            codeInterpreterState.codeBuffer += event.delta
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .writingCode,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.code_interpreter_call_code.done":
            let event = try decoder.decode(ResponsesAPICodeInterpreterCodeDoneEvent.self, from: jsonData)
            let finalCode = event.code ?? codeInterpreterState.codeBuffer
            codeInterpreterState.codeBuffer = finalCode
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .writingCode,
                code: finalCode
            ))

        case "response.code_interpreter_call.interpreting":
            let event = try decoder.decode(ResponsesAPICodeInterpreterStatusEvent.self, from: jsonData)
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .interpreting,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.code_interpreter_call.completed":
            let event = try decoder.decode(ResponsesAPICodeInterpreterStatusEvent.self, from: jsonData)
            return .codeExecutionActivity(CodeExecutionActivity(
                id: event.itemId,
                status: .completed,
                code: codeInterpreterState.codeBuffer
            ))

        case "response.output_item.done":
            if data.contains("\"code_interpreter_call\"") {
                let event = try decoder.decode(ResponsesAPIOutputItemDoneEvent.self, from: jsonData)
                let item = event.item
                if let activity = parseCodeInterpreterOutputItem(item, state: &codeInterpreterState) {
                    return .codeExecutionActivity(activity)
                }
            }
            return nil

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

    func parseCodeInterpreterOutputItem(
        _ item: ResponsesAPIOutputItemAddedEvent.Item,
        state: inout OpenAICodeInterpreterState
    ) -> CodeExecutionActivity? {
        guard let id = item.id else { return nil }

        var stdout: String?
        var outputImages: [CodeExecutionOutputImage]?

        if let outputs = item.outputs {
            var logLines: [String] = []
            var images: [CodeExecutionOutputImage] = []

            for output in outputs {
                if output.type == "logs", let logs = output.logs {
                    logLines.append(logs)
                } else if output.type == "image" {
                    if let url = output.url ?? output.imageUrl {
                        images.append(CodeExecutionOutputImage(url: url))
                    }
                }
            }

            if !logLines.isEmpty {
                stdout = logLines.joined(separator: "\n")
            }
            if !images.isEmpty {
                outputImages = images
            }
        }

        let status: CodeExecutionStatus
        switch item.status {
        case "completed":
            status = .completed
        case "failed":
            status = .failed
        case "incomplete":
            status = .incomplete
        case "interpreting":
            status = .interpreting
        default:
            status = .completed
        }

        state.currentItemID = nil

        return CodeExecutionActivity(
            id: id,
            status: status,
            code: item.code ?? state.codeBuffer,
            stdout: stdout,
            outputImages: outputImages,
            containerID: item.containerId
        )
    }
}
