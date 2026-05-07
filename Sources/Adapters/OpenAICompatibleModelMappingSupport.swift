import Foundation

enum OpenAICompatibleModelMappingSupport {
    static func modelInfo(from model: OpenAIModelsResponse.Model, providerType: ProviderType) -> ModelInfo {
        if providerType == .vercelAIGateway {
            return vercelModelInfo(from: model)
        }
        return ModelCatalog.modelInfo(for: model.id, provider: providerType)
    }

    static func gitHubModelInfo(from model: GitHubModelsCatalogModel) -> ModelInfo? {
        let lowerOutputModalities = Set((model.supportedOutputModalities ?? []).map { $0.lowercased() })
        guard lowerOutputModalities.contains("text") else { return nil }

        if let entry = ModelCatalog.entry(for: model.id, provider: .githubCopilot) {
            return ModelInfo(
                id: model.id,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                maxOutputTokens: entry.maxOutputTokens ?? model.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        let lowerInputModalities = Set((model.supportedInputModalities ?? []).map { $0.lowercased() })
        let lowerCapabilities = Set((model.capabilities ?? []).map { $0.lowercased() })
        let lowerTags = Set((model.tags ?? []).map { $0.lowercased() })

        var capabilities: ModelCapability = []

        if lowerCapabilities.contains("streaming") {
            capabilities.insert(.streaming)
        }
        if lowerInputModalities.contains("image") {
            capabilities.insert(.vision)
        }
        if lowerInputModalities.contains("audio") || lowerOutputModalities.contains("audio") {
            capabilities.insert(.audio)
        }
        if lowerOutputModalities.contains("image") {
            capabilities.insert(.imageGeneration)
        }
        if lowerOutputModalities.contains("video") {
            capabilities.insert(.videoGeneration)
        }
        if lowerInputModalities.contains("pdf")
            || lowerCapabilities.contains("pdf")
            || lowerCapabilities.contains("native_pdf")
            || lowerCapabilities.contains("native-pdf") {
            capabilities.insert(.nativePDF)
        }
        if lowerCapabilities.contains("tool_calling")
            || lowerCapabilities.contains("tool-calling")
            || lowerCapabilities.contains("function_calling")
            || lowerCapabilities.contains("function-calling")
            || lowerCapabilities.contains("tools") {
            capabilities.insert(.toolCalling)
        }
        if lowerCapabilities.contains("reasoning") || lowerCapabilities.contains("thinking") || lowerTags.contains("reasoning") {
            capabilities.insert(.reasoning)
        }
        if lowerCapabilities.contains("prompt_caching")
            || lowerCapabilities.contains("prompt-caching")
            || lowerCapabilities.contains("caching") {
            capabilities.insert(.promptCaching)
        }

        return ModelInfo(
            id: model.id,
            name: normalizedTrimmedString(model.name) ?? model.id,
            capabilities: capabilities,
            contextWindow: max(1, model.maxInputTokens ?? 128_000),
            maxOutputTokens: model.maxOutputTokens,
            reasoningConfig: capabilities.contains(.reasoning)
                ? ModelCapabilityRegistry.defaultReasoningConfig(for: .githubCopilot, modelID: model.id)
                : nil,
            catalogMetadata: gitHubCatalogMetadata(from: model)
        )
    }

    static func isMiMoTTSModelID(_ modelID: String) -> Bool {
        MiMoModelIDs.isTextToSpeechModelID(modelID)
    }

    private static func gitHubCatalogMetadata(from model: GitHubModelsCatalogModel) -> ModelCatalogMetadata? {
        let details = [
            normalizedTrimmedString(model.publisher),
            normalizedTrimmedString(model.summary),
            normalizedTrimmedString(model.rateLimitTier).map { "Rate limit tier: \($0)" }
        ]
        .compactMap { $0 }

        guard !details.isEmpty else { return nil }
        return ModelCatalogMetadata(availabilityMessage: details.joined(separator: "\n"))
    }

    private static func vercelModelInfo(from model: OpenAIModelsResponse.Model) -> ModelInfo {
        let modelID = model.id
        let displayName = normalizedTrimmedString(model.name) ?? modelID

        if let entry = ModelCatalog.entry(for: modelID, provider: .vercelAIGateway) {
            return ModelInfo(
                id: modelID,
                name: entry.displayName,
                capabilities: entry.capabilities,
                contextWindow: entry.contextWindow,
                maxOutputTokens: entry.maxOutputTokens,
                reasoningConfig: entry.reasoningConfig
            )
        }

        var capabilities = derivedVercelCapabilities(from: model)
        let contextWindow = max(1, model.contextWindow ?? 128_000)
        var reasoningConfig = ModelCapabilityRegistry.defaultReasoningConfig(
            for: .vercelAIGateway,
            modelID: modelID
        )
        if !capabilities.contains(.reasoning) {
            reasoningConfig = nil
        }

        if capabilities.contains(.imageGeneration) || capabilities.contains(.videoGeneration) {
            // Media-generation gateway models are not guaranteed to support function tools.
            capabilities.remove(.toolCalling)
            capabilities.remove(.audio)
        }

        return ModelInfo(
            id: modelID,
            name: displayName,
            capabilities: capabilities,
            contextWindow: contextWindow,
            reasoningConfig: reasoningConfig
        )
    }

    private static func derivedVercelCapabilities(from model: OpenAIModelsResponse.Model) -> ModelCapability {
        let lowerType = model.type?.lowercased()
        let lowerTags = Set((model.tags ?? []).map { $0.lowercased() })

        if lowerType == "image" {
            return [.imageGeneration]
        }

        if lowerType == "video" {
            return [.videoGeneration]
        }

        var capabilities: ModelCapability = [.streaming, .toolCalling]

        if lowerTags.contains("reasoning") {
            capabilities.insert(.reasoning)
        }
        if lowerTags.contains("vision") || lowerTags.contains("image-generation") {
            capabilities.insert(.vision)
        }
        if lowerTags.contains("implicit-caching") {
            capabilities.insert(.promptCaching)
        }
        if lowerTags.contains("image-generation") {
            capabilities.insert(.imageGeneration)
        }
        if lowerTags.contains("video-generation") {
            capabilities.insert(.videoGeneration)
        }

        return capabilities
    }
}

struct GitHubModelsCatalogModel: Decodable {
    let id: String
    let name: String?
    let capabilities: [String]?
    let supportedInputModalities: [String]?
    let supportedOutputModalities: [String]?
    let directMaxInputTokens: Int?
    let directMaxOutputTokens: Int?
    let limits: Limits?
    let publisher: String?
    let summary: String?
    let rateLimitTier: String?
    let tags: [String]?

    var maxInputTokens: Int? { directMaxInputTokens ?? limits?.maxInputTokens }
    var maxOutputTokens: Int? { directMaxOutputTokens ?? limits?.maxOutputTokens }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case capabilities
        case supportedInputModalities = "supported_input_modalities"
        case supportedOutputModalities = "supported_output_modalities"
        case directMaxInputTokens = "max_input_tokens"
        case directMaxOutputTokens = "max_output_tokens"
        case limits
        case publisher
        case summary
        case rateLimitTier = "rate_limit_tier"
        case tags
    }

    struct Limits: Decodable {
        let maxInputTokens: Int?
        let maxOutputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case maxInputTokens = "max_input_tokens"
            case maxOutputTokens = "max_output_tokens"
        }
    }
}
