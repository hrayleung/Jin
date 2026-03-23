import Foundation

// MARK: - Model Record Index & Data Tables

extension ModelCatalog {

    // MARK: - Index

    static let lookup: [ProviderType: [String: Record]] = {
        var result: [ProviderType: [String: Record]] = [:]
        for (provider, records) in orderedRecords {
            var providerLookup: [String: Record] = [:]
            for record in records {
                let key = record.id.lowercased()
                precondition(
                    providerLookup[key] == nil,
                    "Duplicate model ID '\(record.id)' in catalog for provider \(provider)"
                )
                providerLookup[key] = record
            }
            result[provider] = providerLookup
        }
        return result
    }()

    static let orderedRecords: [ProviderType: [Record]] = [
        .openai: openAIRecords,
        .codexAppServer: codexAppServerRecords,
        .cloudflareAIGateway: cloudflareAIGatewayRecords,
        .vercelAIGateway: vercelAIGatewayRecords,
        .anthropic: anthropicRecords,
        .perplexity: perplexityRecords,
        .deepinfra: deepInfraRecords,
        .together: togetherRecords,
        .xai: xAIRecords,
        .deepseek: deepSeekRecords,
        .zhipuCodingPlan: zhipuCodingPlanRecords,
        .minimax: minimaxRecords,
        .minimaxCodingPlan: minimaxCodingPlanRecords,
        .fireworks: fireworksRecords,
        .cerebras: cerebrasRecords,
        .sambanova: sambaNovaRecords,
        .morphllm: morphLLMRecords,
        .opencodeGo: opencodeGoRecords,
        .gemini: geminiRecords,
        .vertexai: vertexAIRecords,
        .openrouter: openRouterRecords,
    ]
}
