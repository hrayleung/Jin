import Foundation

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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let event = try decoder.decode(AnthropicStreamEvent.self, from: data)

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

    // MARK: - Search Activity Building

    func searchActivityFromWebSearchResult(
        contentBlock: AnthropicStreamEvent.ContentBlock,
        outputIndex: Int
    ) -> SearchActivity? {
        guard let results = contentBlock.webSearchResults, !results.isEmpty else {
            return nil
        }

        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for result in results {
            guard let rawURL = result.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                continue
            }

            let dedupeKey = rawURL.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)

            var payload: [String: Any] = [
                "type": result.type ?? "web_search_result",
                "url": rawURL
            ]
            if let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                payload["title"] = title
            }
            if let snippet = (result.snippet ?? result.description)?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !snippet.isEmpty {
                payload["snippet"] = snippet
            }
            sources.append(payload)
        }

        guard !sources.isEmpty else { return nil }

        let id = contentBlock.toolUseId ?? contentBlock.id ?? "anthropic_web_search_result_\(outputIndex)"
        let arguments = searchActivityArguments(sources: sources)

        return SearchActivity(
            id: id,
            type: "web_search",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }

    func searchActivityFromTextCitations(
        contentBlock: AnthropicStreamEvent.ContentBlock,
        outputIndex: Int
    ) -> SearchActivity? {
        guard let citations = contentBlock.citations, !citations.isEmpty else {
            return nil
        }

        var sources: [[String: Any]] = []
        var seenURLs: Set<String> = []

        for citation in citations {
            guard citation.type == "web_search_result_location" || citation.type == "search_result_location" else {
                continue
            }

            let rawLocation = citation.url ?? citation.source
            guard let rawURL = rawLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
                continue
            }

            let dedupeKey = rawURL.lowercased()
            guard !seenURLs.contains(dedupeKey) else { continue }
            seenURLs.insert(dedupeKey)

            var payload: [String: Any] = [
                "type": citation.type,
                "url": rawURL
            ]
            if let title = citation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                payload["title"] = title
            }
            if let citedText = citation.citedText?
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !citedText.isEmpty {
                payload["snippet"] = citedText
            }
            sources.append(payload)
        }

        guard !sources.isEmpty else { return nil }

        let id = "anthropic_citation_\(outputIndex)"
        let arguments = searchActivityArguments(sources: sources)

        return SearchActivity(
            id: id,
            type: "url_citation",
            status: .completed,
            arguments: arguments,
            outputIndex: outputIndex,
            sequenceNumber: outputIndex
        )
    }

    func searchActivityArguments(sources: [[String: Any]]) -> [String: AnyCodable] {
        guard !sources.isEmpty else { return [:] }

        var arguments: [String: AnyCodable] = [
            "sources": AnyCodable(sources)
        ]

        if let first = sources.first,
           let firstURL = first["url"] as? String {
            arguments["url"] = AnyCodable(firstURL)
            if let firstTitle = first["title"] as? String, !firstTitle.isEmpty {
                arguments["title"] = AnyCodable(firstTitle)
            }
        }

        return arguments
    }

    // MARK: - Code Execution Activity Building

    func codeExecutionActivityFromToolResult(
        contentBlock: AnthropicStreamEvent.ContentBlock,
        outputIndex: Int
    ) -> CodeExecutionActivity? {
        let id = contentBlock.toolUseId ?? contentBlock.id ?? "anthropic_code_exec_\(outputIndex)"

        guard let resultContent = contentBlock.codeExecutionContent else {
            return CodeExecutionActivity(
                id: id,
                status: .completed
            )
        }

        // Check for error (legacy and current API versions)
        if resultContent.type == "code_execution_tool_result_error"
            || resultContent.type == "bash_code_execution_tool_result_error"
            || resultContent.type == "text_editor_code_execution_tool_result_error" {
            return CodeExecutionActivity(
                id: id,
                status: .failed,
                stderr: resultContent.errorCode
            )
        }

        let status: CodeExecutionStatus = (resultContent.returnCode ?? 0) == 0 ? .completed : .failed
        let outputFiles = resultContent.content?
            .compactMap { output -> CodeExecutionOutputFile? in
                guard let fileID = output.fileId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !fileID.isEmpty else {
                    return nil
                }
                return CodeExecutionOutputFile(id: fileID)
            }

        return CodeExecutionActivity(
            id: id,
            status: status,
            stdout: resultContent.stdout,
            stderr: resultContent.stderr,
            returnCode: resultContent.returnCode,
            outputFiles: outputFiles?.isEmpty == true ? nil : outputFiles
        )
    }

    // MARK: - Code Execution JSON Extraction

    /// Extracts code from accumulated partial JSON.
    /// Handles both legacy `{"code":"..."}` and current `{"command":"..."}` formats.
    /// Since the JSON arrives incrementally, we do a best-effort extraction.
    func extractCodeFromPartialJSON(_ buffer: String) -> String? {
        // Try full JSON parse first
        if let data = buffer.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Try "command" first (current bash_code_execution), then "code" (legacy)
            if let code = dict["command"] as? String { return code }
            if let code = dict["code"] as? String { return code }
        }

        // Best-effort: find the "command" or "code" key and extract the string value
        let codeKeyRange = buffer.range(of: "\"command\"") ?? buffer.range(of: "\"code\"")
        guard let codeKeyRange else { return nil }
        let afterKey = buffer[codeKeyRange.upperBound...]

        // Skip whitespace and colon
        guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = afterKey[afterKey.index(after: colonIndex)...].drop(while: { $0.isWhitespace })

        // Must start with quote
        guard afterColon.first == "\"" else { return nil }
        let stringStart = afterColon.index(after: afterColon.startIndex)
        let remainder = afterColon[stringStart...]

        // Collect characters, handling escape sequences
        var result = ""
        var i = remainder.startIndex
        while i < remainder.endIndex {
            let ch = remainder[i]
            if ch == "\\" {
                let next = remainder.index(after: i)
                if next < remainder.endIndex {
                    let escaped = remainder[next]
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    default: result.append(ch); result.append(escaped)
                    }
                    i = remainder.index(after: next)
                } else {
                    break
                }
            } else if ch == "\"" {
                break
            } else {
                result.append(ch)
                i = remainder.index(after: i)
            }
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Model Info

    func makeModelInfo(from model: AnthropicModelsListResponse.AnthropicModelInfo) -> ModelInfo {
        ModelCatalog.modelInfo(for: model.id, provider: .anthropic, name: model.displayName)
    }
}
