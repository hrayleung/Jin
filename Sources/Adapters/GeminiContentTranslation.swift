import Foundation

extension GeminiAdapter {

    // MARK: - Content Translation

    func translateContents(_ messages: [Message], supportsNativePDF: Bool) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        out.reserveCapacity(messages.count + 4)

        for message in messages where message.role != .system {
            switch message.role {
            case .system:
                continue
            case .tool:
                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    out.append(translateToolResults(toolResults))
                }
            case .user, .assistant:
                out.append(try await translateNonToolMessage(message, supportsNativePDF: supportsNativePDF))

                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    out.append(translateToolResults(toolResults))
                }
            }
        }

        return out
    }

    private func translateNonToolMessage(_ message: Message, supportsNativePDF: Bool) async throws -> [String: Any] {
        let role: String = (message.role == .assistant) ? "model" : "user"

        var parts: [[String: Any]] = []

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
                if let inline = try inlineDataPart(mimeType: image.mimeType, data: image.data, url: image.url) {
                    parts.append(inline)
                }

            case .video(let video):
                if let inline = try inlineDataPart(mimeType: video.mimeType, data: video.data, url: video.url) {
                    parts.append(inline)
                }

            case .audio(let audio):
                if let inline = try inlineDataPart(mimeType: audio.mimeType, data: audio.data, url: audio.url) {
                    parts.append(inline)
                }

            case .file(let file):
                let normalizedFileMIMEType = normalizedMIMEType(file.mimeType)
                let shouldUseHostedFile =
                    googleHostedPromptFileMIMETypes.contains(normalizedFileMIMEType) &&
                    (normalizedFileMIMEType != "application/pdf" || supportsNativePDF)

                if shouldUseHostedFile,
                   let hostedFile = try await uploadHostedGeminiFile(file),
                   let uri = hostedFile.uri {
                    parts.append([
                        "fileData": [
                            "mimeType": hostedFile.mimeType,
                            "fileUri": uri
                        ]
                    ])
                    continue
                }

                if supportsNativePDF, normalizedFileMIMEType == "application/pdf" {
                    let pdfData: Data?
                    if let data = file.data {
                        pdfData = data
                    } else if let url = file.url, url.isFileURL {
                        pdfData = try resolveFileData(from: url)
                    } else {
                        pdfData = nil
                    }

                    if let pdfData {
                        parts.append([
                            "inlineData": [
                                "mimeType": "application/pdf",
                                "data": pdfData.base64EncodedString()
                            ]
                        ])
                        continue
                    }
                }

                let text = googleFileFallbackText(file, providerName: "Gemini API")
                parts.append(["text": text])

            case .thinking, .redactedThinking:
                continue
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

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": role,
            "parts": parts
        ]
    }

    private func translateToolResults(_ results: [ToolResult]) -> [String: Any] {
        var parts: [[String: Any]] = []
        parts.reserveCapacity(results.count)

        for result in results {
            guard let toolName = result.toolName, !toolName.isEmpty else { continue }

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

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return [
            "role": "user",
            "parts": parts
        ]
    }

    func inlineDataPart(mimeType: String, data: Data?, url: URL?) throws -> [String: Any]? {
        try GeminiModelConstants.inlineDataPart(mimeType: mimeType, data: data, url: url)
    }

    private func uploadHostedGeminiFile(_ file: FileContent) async throws -> HostedProviderFileReference? {
        do {
            return try await ProviderHostedFileStore.shared.uploadGeminiFile(
                file: file,
                baseURL: baseURL,
                apiKey: apiKey,
                networkManager: networkManager
            )
        } catch {
            if shouldFallbackFromHostedFileUpload(error) {
                return nil
            }
            throw error
        }
    }

    // MARK: - Stream Event Parsing

    func events(from part: GeminiGenerateContentResponse.Part) -> [StreamEvent] {
        GeminiModelConstants.events(from: part)
    }

    // MARK: - Grounding / Search Activities

    func searchActivities(from grounding: GeminiGenerateContentResponse.GroundingMetadata?) -> [StreamEvent] {
        GoogleGroundingSearchActivities.events(
            from: grounding.map(toSharedGrounding),
            searchPrefix: "gemini-search",
            openPrefix: "gemini-open",
            searchURLPrefix: "gemini-search-url"
        )
    }

    func candidateGroundingMetadata(in candidates: [GeminiGenerateContentResponse.Candidate]?) -> GeminiGenerateContentResponse.GroundingMetadata? {
        guard let candidates else { return nil }
        for candidate in candidates {
            if let grounding = candidate.groundingMetadata {
                return grounding
            }
        }
        return nil
    }

    private func toSharedGrounding(_ g: GeminiGenerateContentResponse.GroundingMetadata) -> GoogleGroundingSearchActivities.GroundingMetadata {
        GeminiModelConstants.toSharedGrounding(g)
    }

    func isCandidateContentFiltered(_ candidate: GeminiGenerateContentResponse.Candidate) -> Bool {
        let reason = (candidate.finishReason ?? "").uppercased()
        if reason == "SAFETY" || reason == "BLOCKED" || reason == "PROHIBITED_CONTENT" {
            return true
        }
        return false
    }

    // MARK: - Model Info Building

    func makeModelInfo(from model: GeminiListModelsResponse.GeminiModel) -> ModelInfo {
        let id = model.id
        let lower = id.lowercased()
        let methods = Set(model.supportedGenerationMethods?.map { $0.lowercased() } ?? [])

        var caps: ModelCapability = []

        let supportsGenerateContent = methods.contains("generatecontent") || methods.contains("streamgeneratecontent") || methods.isEmpty
        let supportsStream = methods.contains("streamgeneratecontent") || methods.isEmpty

        if supportsStream {
            caps.insert(.streaming)
        }

        let isImageModel = isImageGenerationModel(id)
        let isGeminiModel = GeminiModelConstants.knownModelIDs.contains(lower)

        if supportsGenerateContent && !isImageModel {
            caps.insert(.toolCalling)
        }

        if isGeminiModel || isImageModel {
            caps.insert(.vision)
        }

        if supportsGenerateContent && isGeminiModel && !isImageModel {
            caps.insert(.audio)
        }

        var reasoningConfig: ModelReasoningConfig?
        if supportsThinking(id) && isGeminiModel {
            caps.insert(.reasoning)
            if lower == "gemini-3.1-flash-image-preview"
                || lower == "gemini-3.1-flash-lite-preview" {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .minimal)
            } else if supportsThinkingConfig(id) {
                reasoningConfig = ModelReasoningConfig(type: .effort, defaultEffort: .high)
            } else {
                reasoningConfig = nil
            }
        }

        if supportsNativePDF(id) {
            caps.insert(.nativePDF)
        }

        if !isImageModel {
            caps.insert(.promptCaching)
        }

        if ModelCapabilityRegistry.supportsCodeExecution(for: .gemini, modelID: id) {
            caps.insert(.codeExecution)
        }

        if isImageModel {
            caps.insert(.imageGeneration)
        }

        if isVideoGenerationModel(id) {
            caps.insert(.videoGeneration)
        }

        let contextWindow: Int
        if let inputTokenLimit = model.inputTokenLimit {
            contextWindow = inputTokenLimit
        } else if lower == "gemini-3-pro-image-preview" {
            contextWindow = 65_536
        } else if lower == "gemini-3.1-flash-image-preview" {
            contextWindow = 131_072
        } else if lower == "gemini-2.5-flash-image" {
            contextWindow = 32_768
        } else {
            contextWindow = 1_048_576
        }

        return ModelInfo(
            id: id,
            name: model.displayName ?? id,
            capabilities: caps,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig,
            isEnabled: true
        )
    }

}
