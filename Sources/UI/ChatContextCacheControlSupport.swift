import Foundation

extension ChatAuxiliaryControlSupport {
    static func turnOffContextCache(controls: GenerationControls) -> GenerationControls {
        var controls = controls
        controls.contextCache = ContextCacheControls(mode: .off)
        return controls
    }

    static func setImplicitContextCache(
        controls: GenerationControls,
        providerType: ProviderType?
    ) -> GenerationControls {
        var controls = controls
        var cache = controls.contextCache ?? ContextCacheControls(mode: .implicit)
        cache.mode = .implicit

        if providerType != .anthropic {
            cache.strategy = nil
        }
        if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
            cache.cacheKey = nil
        }
        if providerType != .xai {
            cache.minTokensThreshold = nil
        }
        if providerType != .xai {
            cache.conversationID = nil
        }
        if providerType != .gemini && providerType != .vertexai {
            cache.cachedContentName = nil
        }

        controls.contextCache = cache
        return controls
    }

    static func setExplicitContextCache(controls: GenerationControls) -> GenerationControls {
        var controls = controls
        var cache = controls.contextCache ?? ContextCacheControls(mode: .explicit)
        cache.mode = .explicit
        controls.contextCache = cache
        return controls
    }

    static func resetContextCache(controls: GenerationControls) -> GenerationControls {
        var controls = controls
        controls.contextCache = nil
        return controls
    }
}
