import Foundation

enum ChatControlNormalizationSupport {
    static func normalizeGoogleMapsControls(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        supportsGoogleMapsControl: Bool
    ) {
        guard var googleMaps = controls.googleMaps else { return }

        guard supportsGoogleMapsControl else {
            controls.googleMaps = nil
            return
        }

        if providerType != .vertexai {
            googleMaps.languageCode = nil
        }

        if googleMaps.enableWidget != true {
            googleMaps.enableWidget = nil
        }

        controls.googleMaps = googleMaps.isEmpty ? nil : googleMaps
    }

    static func normalizeAnthropicDomainFilters(controls: inout GenerationControls) {
        let allowed = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.allowedDomains)
        let blocked = AnthropicWebSearchDomainUtils.normalizedDomains(controls.webSearch?.blockedDomains)

        if !allowed.isEmpty {
            controls.webSearch?.allowedDomains = allowed
            controls.webSearch?.blockedDomains = nil
        } else if !blocked.isEmpty {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = blocked
        } else {
            controls.webSearch?.allowedDomains = nil
            controls.webSearch?.blockedDomains = nil
        }
    }

    static func defaultWebSearchControls(enabled: Bool, providerType: ProviderType?) -> WebSearchControls {
        guard enabled else { return WebSearchControls(enabled: false) }

        switch providerType {
        case .openai, .openaiWebSocket:
            return WebSearchControls(enabled: true, contextSize: .medium, sources: nil)
        case .perplexity:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        case .xai:
            return WebSearchControls(enabled: true, contextSize: nil, sources: [.web])
        case .anthropic:
            return WebSearchControls(enabled: true)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            return WebSearchControls(enabled: true, contextSize: nil, sources: nil)
        }
    }

    static func ensureValidWebSearchDefaultsIfEnabled(
        controls: inout GenerationControls,
        providerType: ProviderType?
    ) {
        guard controls.webSearch?.enabled == true else { return }
        switch providerType {
        case .openai, .openaiWebSocket:
            controls.webSearch?.sources = nil
            if controls.webSearch?.contextSize == nil {
                controls.webSearch?.contextSize = .medium
            }
        case .perplexity:
            controls.webSearch?.sources = nil
        case .xai:
            controls.webSearch?.contextSize = nil
            let sources = controls.webSearch?.sources ?? []
            if sources.isEmpty {
                controls.webSearch?.sources = [.web]
            }
        case .anthropic:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
            normalizeAnthropicDomainFilters(controls: &controls)
        case .codexAppServer, .githubCopilot, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter, .groq,
             .cohere, .mistral, .deepinfra, .together, .gemini, .vertexai, .deepseek,
             .zhipuCodingPlan, .fireworks, .cerebras, .sambanova, .none:
            controls.webSearch?.contextSize = nil
            controls.webSearch?.sources = nil
        }
    }

    static func normalizeMaxTokensForModel(
        controls: inout GenerationControls,
        modelMaxOutputTokens: Int?
    ) {
        if let modelMaxOutputTokens,
           let requested = controls.maxTokens,
           requested > modelMaxOutputTokens {
            controls.maxTokens = modelMaxOutputTokens
        }
    }

    static func normalizeMediaGenerationOverrides(
        controls: inout GenerationControls,
        supportsMediaGenerationControl: Bool,
        supportsReasoningControl: Bool,
        supportsWebSearchControl: Bool
    ) {
        guard supportsMediaGenerationControl else { return }
        if !supportsReasoningControl {
            controls.reasoning = nil
        }
        if !supportsWebSearchControl {
            controls.webSearch = nil
        }
        controls.searchPlugin = nil
        controls.mcpTools = nil
    }

    static func normalizeVertexAIGenerationConfig(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        lowerModelID: String,
        vertexGemini25TextModelIDs: Set<String>
    ) {
        guard providerType == .vertexai,
              var generationConfig = controls.providerSpecific["generationConfig"]?.value as? [String: Any] else {
            return
        }

        var mutated = false

        if lowerModelID == "gemini-3-pro-image-preview"
            || lowerModelID == "gemini-3.1-flash-image-preview" {
            if generationConfig["thinkingConfig"] != nil {
                generationConfig.removeValue(forKey: "thinkingConfig")
                mutated = true
            }
        } else if vertexGemini25TextModelIDs.contains(lowerModelID),
                  var thinkingConfig = generationConfig["thinkingConfig"] as? [String: Any],
                  thinkingConfig["thinkingLevel"] != nil {
            thinkingConfig.removeValue(forKey: "thinkingLevel")
            if thinkingConfig.isEmpty {
                generationConfig.removeValue(forKey: "thinkingConfig")
            } else {
                generationConfig["thinkingConfig"] = thinkingConfig
            }
            mutated = true
        }

        guard mutated else { return }
        if generationConfig.isEmpty {
            controls.providerSpecific.removeValue(forKey: "generationConfig")
        } else {
            controls.providerSpecific["generationConfig"] = AnyCodable(generationConfig)
        }
    }

    static func normalizeFireworksProviderSpecific(
        controls: inout GenerationControls,
        providerType: ProviderType?,
        isMiniMaxM2FamilyModel: Bool,
        fireworksReasoningHistoryOptions: [String]
    ) {
        guard providerType == .fireworks else { return }

        if isMiniMaxM2FamilyModel {
            controls.providerSpecific.removeValue(forKey: "reasoning_effort")
        }

        if let rawHistory = controls.providerSpecific["reasoning_history"]?.value as? String {
            let normalized = rawHistory.lowercased()
            if fireworksReasoningHistoryOptions.contains(normalized) {
                controls.providerSpecific["reasoning_history"] = AnyCodable(normalized)
            } else {
                controls.providerSpecific.removeValue(forKey: "reasoning_history")
            }
        } else if controls.providerSpecific["reasoning_history"] != nil {
            controls.providerSpecific.removeValue(forKey: "reasoning_history")
        }
    }

    static func normalizeCodexProviderSpecific(
        controls: inout GenerationControls,
        providerType: ProviderType?
    ) {
        guard providerType == .codexAppServer else {
            sanitizeProviderSpecificForProvider(providerType, controls: &controls)
            return
        }

        controls.normalizeCodexProviderSpecific(for: providerType)
    }

    static func normalizeOpenAIServiceTierControls(controls: inout GenerationControls) {
        if controls.openAIServiceTier == nil,
           let legacyRaw = controls.providerSpecific["service_tier"]?.value as? String,
           let legacy = OpenAIServiceTier.normalized(rawValue: legacyRaw) {
            controls.openAIServiceTier = legacy
        }

        if controls.providerSpecific["service_tier"] != nil {
            controls.providerSpecific.removeValue(forKey: "service_tier")
        }
    }

    nonisolated static func sanitizeProviderSpecificForProvider(
        _ providerType: ProviderType?,
        controls: inout GenerationControls
    ) {
        guard providerType != .codexAppServer else { return }
        controls.removeCodexProviderSpecificKeys()
    }

    static func normalizeSearchPluginControls(
        controls: inout GenerationControls,
        modelSupportsBuiltinSearchPluginControl: Bool
    ) {
        if !modelSupportsBuiltinSearchPluginControl {
            controls.searchPlugin = nil
            return
        }

        guard controls.webSearch?.enabled == true else {
            return
        }

        guard var plugin = controls.searchPlugin else {
            return
        }

        if let maxResults = plugin.maxResults {
            plugin.maxResults = max(1, min(50, maxResults))
        }
        if let recencyDays = plugin.recencyDays {
            plugin.recencyDays = max(1, min(365, recencyDays))
        }

        controls.searchPlugin = plugin
    }

    static func normalizeContextCacheControls(
        controls: inout GenerationControls,
        supportsContextCacheControl: Bool,
        supportsExplicitContextCacheMode: Bool,
        supportsContextCacheStrategy: Bool,
        supportsContextCacheTTL: Bool,
        providerType: ProviderType?
    ) {
        if supportsContextCacheControl {
            if var contextCache = controls.contextCache {
                if !supportsExplicitContextCacheMode, contextCache.mode == .explicit {
                    contextCache.mode = .implicit
                    contextCache.cachedContentName = nil
                }
                if !supportsContextCacheStrategy {
                    contextCache.strategy = nil
                } else if contextCache.strategy == nil {
                    contextCache.strategy = .systemOnly
                }
                if !supportsContextCacheTTL {
                    contextCache.ttl = nil
                }
                if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
                    contextCache.cacheKey = nil
                }
                if providerType != .xai {
                    contextCache.minTokensThreshold = nil
                }
                if providerType != .xai {
                    contextCache.conversationID = nil
                }
                if providerType != .gemini && providerType != .vertexai {
                    contextCache.cachedContentName = nil
                }
                if contextCache.mode == .off, providerType != .anthropic {
                    controls.contextCache = nil
                } else {
                    controls.contextCache = contextCache
                }
            }
        } else {
            controls.contextCache = nil
        }
    }

    static func normalizeMCPToolsControls(
        controls: inout GenerationControls,
        supportsMCPToolsControl: Bool
    ) {
        if supportsMCPToolsControl {
            if controls.mcpTools == nil {
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
            } else if controls.mcpTools?.enabledServerIDs?.isEmpty == true {
                controls.mcpTools?.enabledServerIDs = nil
            }
        } else {
            controls.mcpTools = nil
        }
    }

    static func normalizeAnthropicMaxTokens(
        controls: inout GenerationControls,
        supportsReasoningControl: Bool,
        providerType: ProviderType?
    ) {
        if !supportsReasoningControl, providerType == .anthropic {
            controls.maxTokens = nil
        }
        if providerType == .anthropic,
           controls.maxTokens != nil,
           controls.reasoning?.enabled != true {
            controls.maxTokens = nil
        }
    }

    static func normalizeImageGenerationControls(
        controls: inout GenerationControls,
        supportsImageGenerationControl: Bool,
        providerType: ProviderType?,
        supportsCurrentModelImageSizeControl: Bool,
        supportedCurrentModelImageSizes: [ImageOutputSize],
        supportedCurrentModelImageAspectRatios: [ImageAspectRatio],
        lowerModelID: String
    ) {
        if supportsImageGenerationControl {
            if providerType == .openai || providerType == .openaiWebSocket {
                controls.imageGeneration = nil
                controls.xaiImageGeneration = nil
                if var openaiImage = controls.openaiImageGeneration {
                    normalizeOpenAIImageControls(&openaiImage, lowerModelID: lowerModelID)
                    controls.openaiImageGeneration = openaiImage.isEmpty ? nil : openaiImage
                }
            } else if providerType == .xai {
                controls.imageGeneration = nil
                controls.openaiImageGeneration = nil
                if var xaiImage = controls.xaiImageGeneration {
                    xaiImage.quality = nil
                    xaiImage.style = nil
                    if xaiImage.aspectRatio != nil {
                        xaiImage.size = nil
                    }
                    controls.xaiImageGeneration = xaiImage.isEmpty ? nil : xaiImage
                }
            } else {
                if !supportsCurrentModelImageSizeControl {
                    controls.imageGeneration?.imageSize = nil
                } else if let size = controls.imageGeneration?.imageSize,
                          !supportedCurrentModelImageSizes.contains(size) {
                    controls.imageGeneration?.imageSize = nil
                }
                if let ratio = controls.imageGeneration?.aspectRatio,
                   !supportedCurrentModelImageAspectRatios.contains(ratio) {
                    controls.imageGeneration?.aspectRatio = nil
                }
                if providerType != .vertexai {
                    controls.imageGeneration?.vertexPersonGeneration = nil
                    controls.imageGeneration?.vertexOutputMIMEType = nil
                    controls.imageGeneration?.vertexCompressionQuality = nil
                }
                if controls.imageGeneration?.isEmpty == true {
                    controls.imageGeneration = nil
                }
                controls.xaiImageGeneration = nil
                controls.openaiImageGeneration = nil
            }
        } else {
            controls.imageGeneration = nil
            controls.xaiImageGeneration = nil
            controls.openaiImageGeneration = nil
        }
    }

    static func normalizeOpenAIImageControls(
        _ controls: inout OpenAIImageGenerationControls,
        lowerModelID: String
    ) {
        let isGPTImage = lowerModelID.hasPrefix("gpt-image")
        let isDallE3 = lowerModelID.hasPrefix("dall-e-3")
        let isDallE2 = lowerModelID.hasPrefix("dall-e-2")

        if isGPTImage {
            controls.style = nil
        } else if isDallE3 {
            controls.background = nil
            controls.outputFormat = nil
            controls.outputCompression = nil
            controls.moderation = nil
            controls.inputFidelity = nil
            if let quality = controls.quality, quality != .standard && quality != .hd {
                controls.quality = nil
            }
        } else if isDallE2 {
            controls.background = nil
            controls.outputFormat = nil
            controls.outputCompression = nil
            controls.moderation = nil
            controls.inputFidelity = nil
            controls.style = nil
            if let quality = controls.quality, quality != .standard {
                controls.quality = nil
            }
            if let size = controls.size, !OpenAIImageSize.dallE2Sizes.contains(size) {
                controls.size = nil
            }
        }

        if lowerModelID != "gpt-image-1" {
            controls.inputFidelity = nil
        }

        if controls.outputFormat == nil || controls.outputFormat == .png {
            controls.outputCompression = nil
        }
    }

    static func normalizeVideoGenerationControls(
        controls: inout GenerationControls,
        supportsVideoGenerationControl: Bool
    ) {
        if supportsVideoGenerationControl {
            if controls.xaiVideoGeneration?.isEmpty == true {
                controls.xaiVideoGeneration = nil
            }
        } else {
            controls.xaiVideoGeneration = nil
        }
    }
}
