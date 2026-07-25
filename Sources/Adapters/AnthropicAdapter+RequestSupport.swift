import Foundation

extension AnthropicAdapter {
    private struct RequestPreparation {
        let normalizedMessages: [Message]
        let supportsNativePDF: Bool
        let codeExecutionEnabled: Bool
        let cacheStrategy: ContextCacheStrategy
        let blockCacheControl: [String: Any]?
        let topLevelCacheControl: [String: Any]?
        let betaHeader: String?
    }

    var baseURL: String {
        let raw = (providerConfig.baseURL ?? "https://api.anthropic.com/v1").trimmed
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        if providerConfig.type == .databricks {
            // Databricks Unity AI Gateway Anthropic provider service; requests hit
            // `{workspace}/ai-gateway/anthropic/v1/messages` regardless of the pasted path.
            return "\(DatabricksGateway.workspaceRoot(from: trimmed))/ai-gateway/anthropic/v1"
        }

        if providerConfig.type == .kimiForCoding {
            // Kimi for Coding documents `https://api.kimi.com/coding` as the base URL
            // with requests served from `/v1/messages`.
            if trimmed.lowercased().hasSuffix("/v1") {
                return trimmed
            }
            return "\(trimmed)/v1"
        }

        guard providerConfig.type == .mimoTokenPlanAnthropic else {
            return trimmed
        }

        let lower = trimmed.lowercased()
        if lower.hasSuffix("/anthropic/v1") || lower.hasSuffix("/v1") {
            return trimmed
        }
        if lower.hasSuffix("/anthropic") {
            return "\(trimmed)/v1"
        }
        return "\(trimmed)/anthropic/v1"
    }

    var anthropicVersion: String {
        "2023-06-01"
    }

    func anthropicHeaders(apiKey: String, contentType: String? = nil, betaHeader: String? = nil) -> [String: String] {
        if providerConfig.type == .databricks {
            // Unity AI Gateway authenticates with a Databricks token via Bearer and routes to the
            // registered provider service via the Databricks-Model-Provider-Service header (not
            // x-api-key). Beta feature headers are omitted — the gateway forwards a standard body.
            var headers: [String: String] = [
                "Authorization": "Bearer \(apiKey)",
                "anthropic-version": anthropicVersion
            ]
            if let service = DatabricksGateway.providerServiceName(from: providerConfig.baseURL) {
                headers[DatabricksGateway.modelProviderServiceHeader] = service
            }
            if let contentType {
                headers["Content-Type"] = contentType
            }
            return headers
        }

        if providerConfig.type == .mimoTokenPlanAnthropic {
            var headers: [String: String] = ["api-key": apiKey]
            if let contentType {
                headers["Content-Type"] = contentType
            }
            return headers
        }

        var headers: [String: String] = [
            "x-api-key": apiKey,
            "anthropic-version": anthropicVersion
        ]

        if let contentType {
            headers["Content-Type"] = contentType
        }
        if let betaHeader {
            headers["anthropic-beta"] = betaHeader
        }

        return headers
    }

    func buildRequest(
        messages: [Message],
        modelID: String,
        controls: GenerationControls,
        tools: [ToolDefinition],
        streaming: Bool
    ) async throws -> URLRequest {
        let preparation = makeRequestPreparation(
            messages: messages,
            modelID: modelID,
            controls: controls
        )
        let translatedMessages = try await translateMessages(
            preparation.normalizedMessages,
            supportsNativePDF: preparation.supportsNativePDF,
            codeExecutionEnabled: preparation.codeExecutionEnabled,
            cacheControl: preparation.blockCacheControl,
            cacheStrategy: preparation.cacheStrategy
        )

        try AnthropicRequestPreflight.validate(messages: translatedMessages)

        let resolvedMaxTokens = AnthropicModelLimits.resolvedMaxTokens(
            requested: controls.maxTokens,
            for: modelID,
            fallback: 4096
        )

        var body: [String: Any] = [
            "model": modelID,
            "messages": translatedMessages,
            "max_tokens": resolvedMaxTokens,
            "stream": streaming
        ]

        AnthropicRequestBodySupport.applySystemPrompt(
            to: &body,
            from: preparation.normalizedMessages,
            cacheControl: preparation.blockCacheControl
        )
        if let topLevelCacheControl = preparation.topLevelCacheControl {
            body["cache_control"] = topLevelCacheControl
        }
        AnthropicRequestBodySupport.applyThinkingConfig(
            to: &body,
            controls: controls,
            providerType: providerConfig.type,
            modelID: modelID
        )
        AnthropicRequestBodySupport.applySpeedConfig(
            to: &body,
            controls: controls,
            providerType: providerConfig.type,
            modelID: modelID
        )
        let customTools = tools.isEmpty ? [] : (translateTools(tools) as? [[String: Any]] ?? [])
        AnthropicRequestBodySupport.applyToolSpecs(
            to: &body,
            controls: controls,
            customTools: customTools,
            supportsWebSearch: supportsWebSearch(modelID),
            supportsDynamicFiltering: supportsWebSearchDynamicFiltering(modelID),
            codeExecutionEnabled: preparation.codeExecutionEnabled
        )
        if preparation.codeExecutionEnabled,
           let containerID = controls.codeExecution?.anthropic?.normalizedContainerID {
            body["container"] = containerID
        }
        AnthropicRequestBodySupport.applyProviderSpecificOverrides(
            to: &body,
            controls: controls,
            modelID: modelID,
            supportsDynamicFiltering: supportsWebSearchDynamicFiltering(modelID)
        )

        // Must stay last: it reconciles `thinking` against `output_config.effort` once every
        // other mutator (including provider-specific overrides) has had its say.
        AnthropicRequestBodySupport.normalizeDisabledThinkingEffort(in: &body, modelID: modelID)

        return try NetworkRequestFactory.makeJSONRequest(
            url: validatedURL("\(baseURL)/messages"),
            headers: anthropicHeaders(apiKey: apiKey, betaHeader: preparation.betaHeader),
            body: body
        )
    }

    private func supportsNativePDF(_ modelID: String) -> Bool {
        // Claude 4.x families match via the "-4-"/"-4." substrings. The Fable/Mythos 5
        // generation, Opus 5 and Sonnet 5 have no such substring but are fully PDF-capable
        // ("all active models support PDF processing"), and their catalog records declare
        // `.nativePDF` — so they must be matched here too, or PDFs would silently fall back
        // to a filename-only stub (the same regression Fable 5 originally hit).
        let lower = modelID.lowercased()
        return lower.contains("-4-") || lower.contains("-4.")
            || AnthropicModelLimits.isFableMythos5(lower)
            || AnthropicModelLimits.isOpus5(lower)
            || AnthropicModelLimits.isSonnet5(lower)
    }

    private func supportsWebSearch(_ modelID: String) -> Bool {
        modelSupportsWebSearch(providerConfig: providerConfig, modelID: modelID)
    }

    private func supportsWebSearchDynamicFiltering(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsWebSearchDynamicFiltering(
            for: providerConfig.type,
            modelID: modelID
        )
    }

    private func supportsCodeExecution(_ modelID: String) -> Bool {
        ModelCapabilityRegistry.supportsCodeExecution(for: .anthropic, modelID: modelID)
    }

    private func makeRequestPreparation(
        messages: [Message],
        modelID: String,
        controls: GenerationControls
    ) -> RequestPreparation {
        let normalizedMessages = AnthropicToolUseNormalizer.normalize(messages)
        let allowNativePDF = (controls.pdfProcessingMode ?? .native) == .native
        let supportsNativePDF = allowNativePDF && self.supportsNativePDF(modelID)
        let codeExecutionEnabled = controls.codeExecution?.enabled == true && supportsCodeExecution(modelID)
        let cacheStrategy = controls.contextCache?.strategy ?? .systemOnly
        let blockCacheControl = AnthropicRequestBodySupport.blockCacheControl(
            from: controls.contextCache,
            strategy: cacheStrategy
        )
        let topLevelCacheControl = AnthropicRequestBodySupport.topLevelCacheControl(
            from: controls.contextCache,
            strategy: cacheStrategy
        )
        let fastModeEnabled = providerConfig.type == .anthropic
            && controls.anthropicSpeed == .fast
            && AnthropicModelLimits.supportsFastMode(for: modelID)
        let betaHeader = AnthropicRequestPreparationSupport.betaHeader(
            from: controls,
            messages: normalizedMessages,
            codeExecutionEnabled: codeExecutionEnabled,
            fastModeEnabled: fastModeEnabled
        )

        return RequestPreparation(
            normalizedMessages: normalizedMessages,
            supportsNativePDF: supportsNativePDF,
            codeExecutionEnabled: codeExecutionEnabled,
            cacheStrategy: cacheStrategy,
            blockCacheControl: blockCacheControl,
            topLevelCacheControl: topLevelCacheControl,
            betaHeader: betaHeader
        )
    }

    private func translateMessages(
        _ messages: [Message],
        supportsNativePDF: Bool,
        codeExecutionEnabled: Bool,
        cacheControl: [String: Any]?,
        cacheStrategy: ContextCacheStrategy
    ) async throws -> [[String: Any]] {
        let nonSystemMessages = messages.filter { $0.role != .system }
        var translatedMessages: [[String: Any]] = []
        translatedMessages.reserveCapacity(nonSystemMessages.count)

        for message in nonSystemMessages {
            let translated = try await translateMessage(
                message,
                supportsNativePDF: supportsNativePDF,
                usesCodeExecutionTool: codeExecutionEnabled,
                cacheControl: cacheControl,
                cacheStrategy: cacheStrategy
            )
            translatedMessages.append(translated)
        }

        return translatedMessages
    }
}
