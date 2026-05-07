import Foundation

extension ChatControlNormalizationSupport {
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
}
