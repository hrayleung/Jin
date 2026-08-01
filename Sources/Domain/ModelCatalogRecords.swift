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
        .cloudflareAIGateway: cloudflareAIGatewayRecords,
        .vercelAIGateway: vercelAIGatewayRecords,
        .anthropic: anthropicRecords,
        .claudeManagedAgents: anthropicRecords,
        .perplexity: perplexityRecords,
        .mistral: mistralRecords,
        .deepinfra: deepInfraRecords,
        .together: togetherRecords,
        .baseten: basetenRecords,
        .xai: xAIRecords,
        .deepseek: deepSeekRecords,
        .zhipuCodingPlan: zhipuCodingPlanRecords,
        .minimax: minimaxRecords,
        .minimaxCodingPlan: minimaxCodingPlanRecords,
        .mimoTokenPlanOpenAI: mimoTokenPlanOpenAIRecords,
        .mimoTokenPlanAnthropic: mimoTokenPlanAnthropicRecords,
        .kimiForCoding: kimiForCodingRecords,
        .fireworks: fireworksRecords,
        .groq: groqRecords,
        .cerebras: cerebrasRecords,
        .sambanova: sambaNovaRecords,
        .databricks: databricksRecords,
        .modal: modalRecords,
        .morphllm: morphLLMRecords,
        .opencodeGo: opencodeGoRecords,
        .gemini: geminiRecords,
        .vertexai: vertexAIRecords,
        .openrouter: openRouterRecords,
        .zyphra: zyphraRecords,
        .meta: metaRecords,
    ]
}
