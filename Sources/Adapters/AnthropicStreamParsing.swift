import Foundation

private enum AnthropicStreamDecoders {
    static let snakeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

extension AnthropicAdapter {

    // MARK: - SSE Event Parsing

    func parseJSONLine(
        _ line: String,
        currentMessageID: inout String?,
        currentBlockIndex: inout Int?,
        currentToolUse: inout AnthropicToolCallBuilder?,
        currentServerToolUse: inout AnthropicSearchActivityBuilder?,
        currentCodeExecutionID: inout String?,
        currentCodeExecutionCode: inout String,
        currentContentBlockType: inout String?,
        currentThinkingSignature: inout String?,
        usageAccumulator: inout AnthropicUsageAccumulator
    ) throws -> StreamEvent? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        let event = try AnthropicStreamDecoders.snakeDecoder.decode(AnthropicStreamEvent.self, from: data)

        switch event.type {
        case "message_start":
            if let message = event.message {
                currentMessageID = message.id
                usageAccumulator.merge(message.usage)
                return .messageStart(id: message.id)
            }

        case "content_block_start":
            if let index = event.index, let contentBlock = event.contentBlock {
                currentBlockIndex = index
                currentContentBlockType = contentBlock.type

                if contentBlock.type == "thinking" {
                    currentThinkingSignature = contentBlock.signature
                    return .thinkingDelta(.thinking(textDelta: "", signature: currentThinkingSignature))
                }
                if contentBlock.type == "redacted_thinking", let data = contentBlock.data {
                    return .thinkingDelta(.redacted(data: data))
                }

                if contentBlock.type == "server_tool_use" {
                    let id = contentBlock.id ?? UUID().uuidString
                    let name = contentBlock.name ?? "server_tool_use"
                    let arguments = contentBlock.input ?? [:]

                    // Route code_execution server tool use as a code execution activity
                    // Handles both legacy ("code_execution") and current sub-tools
                    // ("bash_code_execution", "text_editor_code_execution")
                    if name == "code_execution"
                        || name == "bash_code_execution"
                        || name == "text_editor_code_execution" {
                        currentCodeExecutionID = id
                        currentCodeExecutionCode = ""
                        return .codeExecutionActivity(CodeExecutionActivity(
                            id: id,
                            status: .inProgress
                        ))
                    }

                    let builder = AnthropicSearchActivityBuilder(id: id, type: name, arguments: arguments)
                    currentServerToolUse = builder
                    return .searchActivity(
                        SearchActivity(
                            id: id,
                            type: name,
                            status: .inProgress,
                            arguments: arguments,
                            outputIndex: index,
                            sequenceNumber: index
                        )
                    )
                }

                if contentBlock.type == "code_execution_tool_result"
                    || contentBlock.type == "bash_code_execution_tool_result"
                    || contentBlock.type == "text_editor_code_execution_tool_result" {
                    let activity = codeExecutionActivityFromToolResult(
                        contentBlock: contentBlock,
                        outputIndex: index
                    )
                    if let activity {
                        return .codeExecutionActivity(activity)
                    }
                }

                if contentBlock.type == "web_search_tool_result",
                   let activity = searchActivityFromWebSearchResult(contentBlock: contentBlock, outputIndex: index) {
                    return .searchActivity(activity)
                }

                if contentBlock.type == "text",
                   let activity = searchActivityFromTextCitations(contentBlock: contentBlock, outputIndex: index) {
                    return .searchActivity(activity)
                }

                if contentBlock.type == "tool_use" {
                    let toolUse = AnthropicToolCallBuilder(
                        id: contentBlock.id ?? UUID().uuidString,
                        name: contentBlock.name ?? ""
                    )
                    currentToolUse = toolUse
                    return .toolCallStart(ToolCall(
                        id: toolUse.id,
                        name: toolUse.name,
                        arguments: [:]
                    ))
                }
            }

        case "content_block_delta":
            if let delta = event.delta {
                if delta.type == "text_delta", let text = delta.text {
                    return .contentDelta(.text(text))
                } else if delta.type == "thinking_delta", let thinking = delta.thinking {
                    return .thinkingDelta(.thinking(textDelta: thinking, signature: currentThinkingSignature))
                } else if delta.type == "signature_delta", let signature = delta.signature {
                    if currentThinkingSignature == nil {
                        currentThinkingSignature = signature
                    } else {
                        currentThinkingSignature? += signature
                    }
                    return .thinkingDelta(.thinking(textDelta: "", signature: currentThinkingSignature))
                } else if delta.type == "input_json_delta", let partialJSON = delta.partialJson {
                    if currentContentBlockType == "server_tool_use",
                       let codeExecID = currentCodeExecutionID {
                        // Accumulate code from the code_execution server tool input
                        currentCodeExecutionCode.append(partialJSON)
                        // Try to extract code from the accumulated JSON so far
                        let extractedCode = extractCodeFromPartialJSON(currentCodeExecutionCode)
                        return .codeExecutionActivity(CodeExecutionActivity(
                            id: codeExecID,
                            status: .writingCode,
                            code: extractedCode
                        ))
                    } else if currentContentBlockType == "server_tool_use",
                       let currentServerToolUse {
                        currentServerToolUse.appendArguments(partialJSON)
                        if let updated = currentServerToolUse.build(status: .searching, outputIndex: currentBlockIndex) {
                            return .searchActivity(updated)
                        }
                        return nil
                    } else if let currentToolUse {
                        currentToolUse.appendArguments(partialJSON)
                        return .toolCallDelta(id: currentToolUse.id, argumentsDelta: partialJSON)
                    }
                }
            }

        case "content_block_stop":
            if currentContentBlockType == "thinking" {
                currentThinkingSignature = nil
            }

            if currentContentBlockType == "server_tool_use",
               let codeExecID = currentCodeExecutionID {
                let extractedCode = extractCodeFromPartialJSON(currentCodeExecutionCode)
                currentCodeExecutionID = nil
                currentCodeExecutionCode = ""
                currentContentBlockType = nil
                currentBlockIndex = nil
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
                return .codeExecutionActivity(CodeExecutionActivity(
                    id: codeExecID,
                    status: .interpreting,
                    code: extractedCode
                ))
            }

            if currentContentBlockType == "server_tool_use",
               let serverToolUse = currentServerToolUse,
               let completed = serverToolUse.build(status: .completed, outputIndex: currentBlockIndex) {
                currentContentBlockType = nil
                currentBlockIndex = nil
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
                return .searchActivity(completed)
            }
            currentContentBlockType = nil

            if let toolUse = currentToolUse {
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
                let toolCall = try toolUse.build()
                return .toolCallEnd(toolCall)
            }

            self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)

        case "message_delta":
            if let usage = event.usage {
                usageAccumulator.merge(usage)
                return .messageEnd(usage: usageAccumulator.toUsage())
            }

        case "message_stop":
            return .messageEnd(usage: usageAccumulator.toUsage())

        default:
            break
        }

        return nil
    }

    func currentToolCleanup(
        currentToolUse: inout AnthropicToolCallBuilder?,
        currentServerToolUse: inout AnthropicSearchActivityBuilder?
    ) {
        currentToolUse = nil
        currentServerToolUse = nil
    }
}
