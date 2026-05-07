import Foundation

extension OpenAICompatibleAdapter {
    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": modelID,
            "messages": try translateMessages(messages, modelID: modelID),
            "stream": streaming
        ]

        let requestShape = ModelCapabilityRegistry.requestShape(for: providerConfig.type, modelID: modelID)
        let shouldOmitSamplingControls = OpenAICompatibleReasoningSupport.applyReasoning(
            to: &body,
            controls: controls,
            providerConfig: providerConfig,
            modelID: modelID,
            requestShape: requestShape
        )

        OpenAICompatibleRequestSupport.applySamplingControls(
            to: &body,
            controls: controls,
            shouldOmitSamplingControls: shouldOmitSamplingControls
        )

        OpenAICompatibleRequestSupport.applyMaxTokens(
            to: &body,
            controls: controls,
            providerType: providerConfig.type
        )

        OpenAICompatibleRequestSupport.applyOpenAIServiceTier(
            to: &body,
            controls: controls,
            providerType: providerConfig.type
        )

        let functionTools = tools.isEmpty ? [] : (translateTools(tools) as? [[String: Any]] ?? [])
        let toolObjects = OpenAICompatibleRequestSupport.miMoToolObjects(
            webSearch: providerConfig.type == .mimoTokenPlanOpenAI ? controls.webSearch : nil,
            supportsNativeWebSearch: ModelCapabilityRegistry.supportsWebSearch(
                for: providerConfig.type,
                modelID: modelID
            ),
            functionTools: functionTools
        )

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        OpenAICompatibleRequestSupport.applyProviderSpecificOverrides(
            to: &body,
            controls: controls,
            providerConfig: providerConfig,
            modelID: modelID
        )

        OpenAICompatibleReasoningSupport.finalizeOpenAICompatibleReasoningBody(
            &body,
            controls: controls,
            providerConfig: providerConfig,
            modelID: modelID
        )

        var request = try makeAuthorizedJSONRequest(
            url: validatedURL("\(baseURL)/chat/completions"),
            apiKey: apiKey,
            authHeader: providerAuthenticationHeader(apiKey: apiKey),
            body: body,
            accept: acceptHeaderValue,
            includeUserAgent: false
        )
        applyProviderHeaders(to: &request)
        applyCloudflareGatewayCacheHeaders(to: &request, controls: controls)
        return request
    }

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        try translateMessagesToOpenAIFormat(messages) { message in
            try translateNonToolMessage(message, modelID: modelID)
        }
    }

    private func translateNonToolMessage(_ message: Message, modelID: String) throws -> [String: Any] {
        let supportsAudioInput = supportsAudioInput(modelID: modelID)
        let supportsVideoInput = supportsVideoInput(modelID: modelID)
        let split = splitContentParts(
            message.content,
            separator: "\n",
            includeImages: true,
            includeAudio: supportsAudioInput,
            includeVideo: supportsVideoInput
        )

        var dict: [String: Any] = [
            "role": message.role.rawValue
        ]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .assistant:
            if let thinking = split.thinkingOrNil {
                if OpenAICompatibleReasoningSupport.isMistralMedium35Model(
                    providerConfig: providerConfig,
                    modelID: modelID
                ) {
                    dict["content"] = mistralAssistantContentChunks(visible: split.visible, thinking: thinking)
                } else if providerConfig.type == .zhipuCodingPlan
                    || providerConfig.type == .minimax
                    || providerConfig.type == .mimoTokenPlanOpenAI {
                    dict["content"] = split.visible
                    dict["reasoning_content"] = thinking
                } else {
                    dict["content"] = split.visible
                    dict["reasoning"] = thinking
                }
            } else {
                dict["content"] = split.visible
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .user:
            if split.hasRichUserContent {
                let audioBuilder: ((AudioContent) throws -> [String: Any]?)? = {
                    guard supportsAudioInput else { return nil }
                    return providerConfig.type == .mimoTokenPlanOpenAI ? mimoInputAudioPart : mistralAudioPartBuilder
                }()
                dict["content"] = try translateUserContentPartsToOpenAIFormat(
                    message.content,
                    audioPartBuilder: audioBuilder,
                    videoPartBuilder: supportsVideoInput ? mimoInputVideoPart : nil
                )
            } else {
                dict["content"] = split.visible
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    private func supportsAudioInput(modelID: String) -> Bool {
        if OpenAICompatibleReasoningSupport.isMistralMedium35Model(
            providerConfig: providerConfig,
            modelID: modelID
        ) {
            return false
        }
        if providerConfig.type == .mimoTokenPlanOpenAI {
            return Self.miMoFullModalInputModelIDs.contains(modelID.lowercased())
        }
        return true
    }

    private func supportsVideoInput(modelID: String) -> Bool {
        providerConfig.type == .mimoTokenPlanOpenAI
            && Self.miMoFullModalInputModelIDs.contains(modelID.lowercased())
    }

    private func mistralAssistantContentChunks(visible: String, thinking: String) -> [[String: Any]] {
        var chunks: [[String: Any]] = [
            [
                "type": "thinking",
                "thinking": [
                    [
                        "type": "text",
                        "text": thinking
                    ]
                ],
                "closed": true
            ]
        ]

        if !visible.isEmpty {
            chunks.append([
                "type": "text",
                "text": visible
            ])
        }

        return chunks
    }

    /// Mistral Voxtral expects a raw base64 string for `input_audio`, not the standard OpenAI format.
    private func mistralAudioPartBuilder(_ audio: AudioContent) throws -> [String: Any]? {
        if providerConfig.type == .mistral {
            guard let payloadData = try resolveAudioData(audio) else { return nil }
            return [
                "type": "input_audio",
                "input_audio": payloadData.base64EncodedString()
            ]
        }
        return try openAIInputAudioPart(audio)
    }

    private func mimoInputAudioPart(_ audio: AudioContent) throws -> [String: Any]? {
        if let url = audio.url, !url.isFileURL {
            return [
                "type": "input_audio",
                "input_audio": ["data": url.absoluteString]
            ]
        }
        guard let payloadData = try resolveAudioData(audio) else { return nil }
        return [
            "type": "input_audio",
            "input_audio": [
                "data": mediaDataURI(mimeType: audio.mimeType, data: payloadData)
            ]
        ]
    }

    private func mimoInputVideoPart(_ video: VideoContent) throws -> [String: Any]? {
        let urlString: String?
        if let url = video.url, !url.isFileURL {
            urlString = url.absoluteString
        } else if let payloadData = try resolveVideoData(video) {
            urlString = mediaDataURI(mimeType: video.mimeType, data: payloadData)
        } else {
            urlString = nil
        }
        guard let urlString else { return nil }

        return [
            "type": "video_url",
            "video_url": ["url": urlString],
            "fps": 2,
            "media_resolution": "default"
        ]
    }

    private static let miMoFullModalInputModelIDs: Set<String> = [
        MiMoModelIDs.v25,
        MiMoModelIDs.v2Omni
    ]

    func isMistralTranscriptionOnlyModelID(_ lowerModelID: String) -> Bool {
        lowerModelID == "voxtral-mini-2602" || lowerModelID.contains("transcribe")
    }
}
