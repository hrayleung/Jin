import Foundation

extension AnthropicAdapter {

    // MARK: - SSE Event Parsing

    func parseJSONLine(
        _ line: String,
        currentMessageID: inout String?,
        currentBlockIndex: inout Int?,
        currentToolUse: inout AnthropicToolCallBuilder?,
        currentServerToolUse: inout AnthropicSearchActivityBuilder?,
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
               let serverToolUse = currentServerToolUse,
               let completed = serverToolUse.build(status: .completed, outputIndex: currentBlockIndex) {
                currentContentBlockType = nil
                currentBlockIndex = nil
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
                return .searchActivity(completed)
            }
            currentContentBlockType = nil

            if let toolUse = currentToolUse, let toolCall = toolUse.build() {
                self.currentToolCleanup(currentToolUse: &currentToolUse, currentServerToolUse: &currentServerToolUse)
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

    // MARK: - Model Info

    func makeModelInfo(from model: AnthropicModelsListResponse.AnthropicModelInfo) -> ModelInfo {
        ModelCatalog.modelInfo(for: model.id, provider: .anthropic, name: model.displayName)
    }
}
