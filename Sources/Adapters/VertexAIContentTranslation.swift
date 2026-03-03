import Foundation

extension VertexAIAdapter {

    // MARK: - Content Translation

    func translateMessage(_ message: Message, supportsNativePDF: Bool) -> [String: Any] {
        let role: String = (message.role == .assistant) ? "model" : "user"

        var parts: [[String: Any]] = []

        if message.role != .tool {
            if message.role == .assistant {
                for part in message.content {
                    if case .thinking(let thinking) = part {
                        var dict: [String: Any] = [
                            "text": thinking.text,
                            "thought": true
                        ]
                        if let signature = thinking.signature {
                            dict["thoughtSignature"] = signature
                        }
                        parts.append(dict)
                    }
                }
            }

            for part in message.content {
                switch part {
                case .text(let text):
                    parts.append(["text": text])
                case .image(let image):
                    if let data = image.data {
                        parts.append([
                            "inlineData": [
                                "mimeType": image.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = image.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        parts.append([
                            "inlineData": [
                                "mimeType": image.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .video(let video):
                    if let data = video.data {
                        parts.append([
                            "inlineData": [
                                "mimeType": video.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = video.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        parts.append([
                            "inlineData": [
                                "mimeType": video.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .audio(let audio):
                    if let data = audio.data {
                        parts.append([
                            "inlineData": [
                                "mimeType": audio.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    } else if let url = audio.url, url.isFileURL, let data = try? Data(contentsOf: url) {
                        parts.append([
                            "inlineData": [
                                "mimeType": audio.mimeType,
                                "data": data.base64EncodedString()
                            ]
                        ])
                    }
                case .file(let file):
                    if supportsNativePDF && file.mimeType == "application/pdf" {
                        let pdfData: Data?
                        if let data = file.data {
                            pdfData = data
                        } else if let url = file.url, url.isFileURL {
                            pdfData = try? Data(contentsOf: url)
                        } else {
                            pdfData = nil
                        }

                        if let pdfData = pdfData {
                            parts.append([
                                "inlineData": [
                                    "mimeType": "application/pdf",
                                    "data": pdfData.base64EncodedString()
                                ]
                            ])
                            continue
                        }
                    }

                    let text = AttachmentPromptRenderer.fallbackText(for: file)
                    parts.append(["text": text])
                case .thinking, .redactedThinking:
                    break
                }
            }
        }

        if message.role == .assistant, let toolCalls = message.toolCalls {
            for call in toolCalls {
                var part: [String: Any] = [
                    "functionCall": [
                        "name": call.name,
                        "args": call.arguments.mapValues { $0.value }
                    ]
                ]
                if let signature = call.signature {
                    part["thoughtSignature"] = signature
                }
                parts.append(part)
            }
        }

        if message.role == .tool, let toolResults = message.toolResults {
            for result in toolResults {
                guard let toolName = result.toolName else { continue }
                var part: [String: Any] = [
                    "functionResponse": [
                        "name": toolName,
                        "response": [
                            "content": result.content
                        ]
                    ]
                ]
                if let signature = result.signature {
                    part["thoughtSignature"] = signature
                }
                parts.append(part)
            }
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": role,
            "parts": parts
        ]
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

    func parseStreamChunk(_ data: String) throws -> (events: [StreamEvent], usage: Usage?) {
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else {
            return ([], nil)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if trimmed.hasPrefix("[") {
            let responses = try decoder.decode([VertexGenerateContentResponse].self, from: jsonData)
            var events: [StreamEvent] = []
            var usage: Usage?
            for response in responses {
                events.append(contentsOf: eventsFromVertexResponse(response))
                if let parsed = usageFromVertexResponse(response) {
                    usage = parsed
                }
            }
            return (events, usage)
        }

        let response = try decoder.decode(VertexGenerateContentResponse.self, from: jsonData)
        return (eventsFromVertexResponse(response), usageFromVertexResponse(response))
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

    func eventsFromVertexResponse(_ response: VertexGenerateContentResponse) -> [StreamEvent] {
        var events: [StreamEvent] = []

        if let candidate = response.candidates?.first,
           let content = candidate.content {
            for part in content.parts ?? [] {
                if let text = part.text {
                    if part.thought == true {
                        events.append(.thinkingDelta(.thinking(textDelta: text, signature: part.thoughtSignature)))
                    } else {
                        events.append(.contentDelta(.text(text)))
                    }
                }

                if let functionCall = part.functionCall {
                    let id = UUID().uuidString
                    let toolCall = ToolCall(
                        id: id,
                        name: functionCall.name,
                        arguments: functionCall.args ?? [:],
                        signature: part.thoughtSignature
                    )
                    events.append(.toolCallStart(toolCall))
                    events.append(.toolCallEnd(toolCall))
                }

                if let inline = part.inlineData,
                   let base64 = inline.data,
                   let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    let mimeType = inline.mimeType ?? "image/png"
                    if mimeType.lowercased().hasPrefix("image/") {
                        events.append(.contentDelta(.image(ImageContent(mimeType: mimeType, data: data))))
                    }
                }
            }
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

    private func toSharedGrounding(_ g: VertexGenerateContentResponse.GroundingMetadata) -> GoogleGroundingSearchActivities.GroundingMetadata {
        GoogleGroundingSearchActivities.GroundingMetadata(
            webSearchQueries: g.webSearchQueries,
            retrievalQueries: g.retrievalQueries,
            groundingChunks: g.groundingChunks?.map {
                .init(webURI: $0.web?.uri, webTitle: $0.web?.title)
            },
            groundingSupports: g.groundingSupports?.map {
                .init(segmentText: $0.segment?.text, groundingChunkIndices: $0.groundingChunkIndices)
            },
            searchEntryPoint: g.searchEntryPoint.map {
                .init(sdkBlob: $0.sdkBlob)
            }
        )
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
