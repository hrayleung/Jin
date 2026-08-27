import Foundation

extension ChatAuxiliaryControlSupport {
    static func automaticContextCacheControls(
        providerType: ProviderType?,
        modelID: String,
        modelCapabilities: ModelCapability?,
        supportsMediaGenerationControl: Bool,
        conversationID: UUID
    ) -> ContextCacheControls? {
        guard !supportsMediaGenerationControl else { return nil }
        guard let providerType else { return nil }
        if providerType != .cloudflareAIGateway,
           let modelCapabilities,
           !modelCapabilities.contains(.promptCaching) {
            return nil
        }

        let cacheConversationID = automaticContextCacheConversationID(
            conversationID: conversationID,
            modelID: modelID
        )

        switch providerType {
        case .openai, .openaiWebSocket, .meta:
            return ContextCacheControls(mode: .implicit)
        case .mimoTokenPlanAnthropic, .mimoTokenPlanOpenAI, .kimiForCoding:
            return nil
        case .xai:
            return ContextCacheControls(
                mode: .implicit,
                conversationID: cacheConversationID
            )
        case .anthropic:
            return ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .providerDefault
            )
        case .claudeManagedAgents:
            return ContextCacheControls(
                mode: .implicit,
                strategy: .prefixWindow,
                ttl: .providerDefault
            )
        case .gemini, .vertexai:
            return ContextCacheControls(mode: .implicit)
        case .cloudflareAIGateway:
            return ContextCacheControls(mode: .implicit, ttl: .minutes5)
        // Router passes provider cache controls through rather than owning a cache, and
        // exposes no cache resource of its own — the upstream's implicit caching still
        // applies without Jin sending anything.
        case .githubCopilot, .openaiCompatible, .vercelAIGateway, .openrouter, .perplexity, .groq, .cohere,
             .mistral, .deepinfra, .together, .baseten, .runinfra, .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks,
             .cerebras, .sambanova, .databricks, .modal, .morphllm, .opencodeGo, .router, .zyphra, .makora:
            return nil
        }
    }

    static func automaticContextCacheConversationID(conversationID: UUID, modelID: String) -> String {
        let conversationPart = conversationID.uuidString.lowercased()
        let modelPart = sanitizedContextCacheIdentifier(modelID, maxLength: 32)
        return "jin-conv-\(conversationPart)-\(modelPart)"
    }

    static func sanitizedContextCacheIdentifier(_ raw: String, maxLength: Int) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let lower = raw.lowercased()
        var output = ""
        output.reserveCapacity(min(lower.count, maxLength))

        var previousWasHyphen = false
        for scalar in lower.unicodeScalars {
            guard output.count < maxLength else { break }
            let character = Character(scalar)
            if allowed.contains(character) {
                output.append(character)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                output.append("-")
                previousWasHyphen = true
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "model" : trimmed
    }
}
