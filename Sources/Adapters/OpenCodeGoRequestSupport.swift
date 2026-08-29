import Foundation

extension OpenCodeGoAdapter {
    /// Models OpenCode Go serves via the Anthropic-style `/messages` endpoint
    /// (per opencode.ai/docs/go + models.dev `opencode-go` → `@ai-sdk/anthropic`).
    /// Besides Claude, OpenCode Go routes the MiniMax and Qwen families through
    /// `/messages`; everything else (DeepSeek, GLM, Kimi, MiMo, …) uses `/chat/completions`.
    /// Matched by exact ID (see `anthropicMessagesModelIDs`), never by prefix.
    static func usesAnthropicMessagesEndpoint(_ modelID: String) -> Bool {
        anthropicMessagesModelIDs.contains(modelID.lowercased())
    }

    /// Models OpenCode Go serves via the OpenAI Responses `/responses` endpoint (per
    /// opencode.ai/docs/go's endpoint table + models.dev `opencode-go` → `@ai-sdk/openai`):
    /// GPT-5.6 Luna, Grok 4.6, and Muse Spark 1.2 / 1.2 Contributor. Matched by exact ID
    /// (see `openAIResponsesModelIDs`), never by prefix. Muse Spark still matches so
    /// `validateAPIKey` probes `/responses`; `sendMessage` then forwards Muse IDs
    /// to `MetaAdapter` (see `usesMuseSparkResponsesEndpoint`). Grok 4.5 is not in this
    /// set — it stays on `/chat/completions`.
    static func usesOpenAIResponsesEndpoint(_ modelID: String) -> Bool {
        openAIResponsesModelIDs.contains(modelID.lowercased())
    }

    /// Muse Spark IDs that need Meta's encrypted-reasoning request/replay on
    /// `/responses`. Exact IDs from live Go `/models`.
    static func usesMuseSparkResponsesEndpoint(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.isOpenCodeGoMuseSparkModelID(modelID.lowercased())
    }

    /// Whether this `/chat/completions` model accepts a caller-supplied `temperature`.
    /// Matched by exact ID (see `temperatureUnsupportedChatCompletionsModelIDs`).
    static func supportsCustomTemperature(_ modelID: String) -> Bool {
        !temperatureUnsupportedChatCompletionsModelIDs.contains(modelID.lowercased())
    }

    func buildOpenAIRequest(
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

        // Moonshot Kimi models on Go reject non-default temperatures with HTTP 400
        // ("invalid temperature: only 1 is allowed for this model"). Jin's assistant
        // default is 0.1, so always omit rather than force 1.0 — the gateway applies the
        // only legal value (and the mode-correct 1.0/0.6 pair for K2.5/K2.6).
        let supportsTemperature = Self.supportsCustomTemperature(modelID)
        if supportsTemperature, let temperature = controls.temperature {
            body["temperature"] = temperature
        }
        if let maxTokens = controls.maxTokens {
            body["max_tokens"] = maxTokens
        }
        if let topP = controls.topP {
            body["top_p"] = topP
        }

        // OpenCode Go's gateway is a strict OpenAI-compatible /chat/completions proxy that
        // rejects unknown top-level fields ("Extra inputs are not permitted"). The nested
        // {"reasoning": {"effort": …}} object is the OpenAI Responses-API / OpenRouter shape,
        // not a chat/completions field, so it 400s. Send the standard top-level
        // `reasoning_effort` STRING instead. These models (GLM, DeepSeek, Kimi, MiMo) reason
        // by default, so to disable we omit the field entirely rather than send an
        // unsupported value — `reasoning_content` still streams back in the response.
        // GLM-5.3 and Ox Alpha Free cannot disable thinking, so a disabled/legacy Off
        // control is sent as `low` rather than omitted (default max).
        // LongCat-2.0's native thinking object is unverified on Go (extra top-level
        // fields 400). Do not emit `reasoning_effort` either — models.dev only lists a
        // toggle, and the catalog has no effort config.
        let omitReasoningEffort = modelID.lowercased() == "longcat-2.0"

        if omitReasoningEffort {
            // Leave thinking to the gateway default.
        } else if Self.usesAlwaysOnLowHighMaxReasoningEffort(modelID) {
            let effort: ReasoningEffort
            if let reasoning = controls.reasoning, reasoning.enabled, let requested = reasoning.effort, requested != ReasoningEffort.none {
                effort = requested
            } else if let reasoning = controls.reasoning, !reasoning.enabled || reasoning.effort == ReasoningEffort.none {
                effort = .low
            } else {
                effort = .max
            }
            body["reasoning_effort"] = mapReasoningEffort(effort, modelID: modelID)
        } else if let reasoning = controls.reasoning,
           reasoning.enabled,
           let effort = reasoning.effort,
           effort != .none {
            body["reasoning_effort"] = mapReasoningEffort(effort, modelID: modelID)
        }

        var toolObjects: [[String: Any]] = []

        if controls.webSearch?.enabled == true,
           ModelCapabilityRegistry.supportsWebSearch(for: providerConfig.type, modelID: modelID) {
            toolObjects.append(buildWebSearchTool(from: controls.webSearch))
        }

        if !tools.isEmpty, let functionTools = translateTools(tools) as? [[String: Any]] {
            toolObjects.append(contentsOf: functionTools)
        }

        if !toolObjects.isEmpty {
            body["tools"] = toolObjects
        }

        for (key, value) in controls.providerSpecific {
            // Never let a custom param reintroduce the nested `reasoning` object the strict
            // gateway rejects (HTTP 400); reasoning is controlled via `reasoning_effort` above.
            guard key != "reasoning" else { continue }
            // Same for temperature on fixed-temp models — a stale providerSpecific value
            // would re-trigger the gateway's "only 1 is allowed" 400.
            if !supportsTemperature, key == "temperature" { continue }
            body[key] = value.value
        }

        return try makeAuthorizedJSONRequest(
            url: validatedURL("\(Self.hardcodedBaseURL)/chat/completions"),
            apiKey: apiKey,
            body: body
        )
    }

    /// Exact IDs whose thinking cannot be turned off and whose `reasoning_effort`
    /// band is low/high/max (default max). Off maps to `low`.
    static func usesAlwaysOnLowHighMaxReasoningEffort(_ modelID: String) -> Bool {
        switch modelID.lowercased() {
        case "glm-5.3", "glm-5.3-flash", "ox-alpha-free":
            return true
        default:
            return false
        }
    }

    private func translateMessages(_ messages: [Message], modelID: String) throws -> [[String: Any]] {
        let includeVideo = modelSupportsVideoInput(providerConfig: providerConfig, modelID: modelID)
        let visionUserImagesOnly = modelID.lowercased() == "deepseek-v4-flash-vision-exp"
        return try translateMessagesToOpenAIFormat(messages) { message in
            try translateNonToolMessage(
                message,
                includeVideo: includeVideo,
                includeImages: !visionUserImagesOnly || message.role == .user
            )
        }
    }

    private func translateNonToolMessage(
        _ message: Message,
        includeVideo: Bool,
        includeImages: Bool
    ) throws -> [String: Any] {
        let split = splitContentParts(
            message.content,
            includeImages: includeImages,
            includeAudio: true,
            includeVideo: includeVideo
        )

        var dict: [String: Any] = ["role": message.role.rawValue]

        switch message.role {
        case .system:
            dict["content"] = split.visible

        case .user:
            if split.hasRichUserContent {
                dict["content"] = try translateUserContentPartsToOpenAIFormat(
                    message.content,
                    videoPartBuilder: includeVideo ? openAIInputVideoPart : nil
                )
            } else {
                dict["content"] = split.visible
            }

        case .assistant:
            let hasToolCalls = (message.toolCalls?.isEmpty == false)
            if split.visible.isEmpty {
                dict["content"] = hasToolCalls ? NSNull() : ""
            } else {
                dict["content"] = split.visible
            }

            if !split.thinking.isEmpty {
                dict["reasoning_content"] = split.thinking
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                dict["tool_calls"] = translateToolCallsToOpenAIFormat(toolCalls)
            }

        case .tool:
            dict["content"] = split.visible
        }

        return dict
    }

    private func mapReasoningEffort(_ effort: ReasoningEffort, modelID: String) -> String {
        switch modelID.lowercased() {
        case "glm-5.3", "glm-5.3-flash", "ox-alpha-free":
            // Official band is low/high/max (default max). Disabled thinking is
            // no longer supported and maps to `low`. Medium is not a valid wire
            // value — fold it to high.
            switch effort {
            case .none, .minimal, .low:
                return "low"
            case .medium, .high:
                return "high"
            case .xhigh, .max:
                return "max"
            }
        case "glm-5.2":
            // GLM-5.2 exposes only `high` and `max` (its native default). Honor `max` rather
            // than clamping it to `high` like the shared none/low/medium/high mapping does,
            // and never emit the invalid `low`/`medium` strings for it. The model's selectable
            // efforts are already restricted to [.high, .max] in ModelCapabilityRegistry.
            return (effort == .max || effort == .xhigh) ? "max" : "high"
        case "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp":
            // Official DeepSeek V4 OpenAI format is low/high/max. On V4 Pro, xhigh/max
            // map to max and everything else maps to high (api-docs.deepseek.com
            // thinking_mode, 2026-08). The Go UI band is already [.high, .max].
            return (effort == .max || effort == .xhigh) ? "max" : "high"
        case "hy3", "hy3-preview":
            // Hy3 accepts only `low`/`high`; the shared mapper would emit an invalid "medium"
            // for an effort inherited from another model that bypassed the registry's clamp.
            return (effort == .minimal || effort == .low) ? "low" : "high"
        case "hy4-preview":
            // Hy4 preview on Go: only `high` is a verified wire value. `low` is Hy3's
            // extra rung and is unverified here; fold everything enabled to `high`.
            return "high"
        default:
            return mapReasoningEffortNoneDisabled(effort)
        }
    }

    private func buildWebSearchTool(from controls: WebSearchControls?) -> [String: Any] {
        var tool: [String: Any] = ["type": "web_search"]

        if let limit = controls?.maxUses, limit > 0 {
            tool["limit"] = limit
        }

        if let location = controls?.userLocation,
           let userLocation = buildUserLocation(location) {
            tool["user_location"] = userLocation
        }

        return tool
    }

    private func buildUserLocation(_ location: WebSearchUserLocation) -> [String: Any]? {
        var userLocation: [String: Any] = ["type": "approximate"]

        if let country = normalizedWebSearchLocationField(location.country) {
            userLocation["country"] = country
        }
        if let region = normalizedWebSearchLocationField(location.region) {
            userLocation["region"] = region
        }
        if let city = normalizedWebSearchLocationField(location.city) {
            userLocation["city"] = city
        }

        return userLocation.count > 1 ? userLocation : nil
    }

    private func normalizedWebSearchLocationField(_ value: String?) -> String? {
        value?.trimmedNonEmpty
    }
}
