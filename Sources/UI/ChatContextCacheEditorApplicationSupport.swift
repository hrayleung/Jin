import Foundation

extension ChatAuxiliaryControlSupport {
    static func applyContextCacheDraft(
        draft: ContextCacheControls,
        ttlPreset: ContextCacheTTLPreset,
        customTTLDraft: String,
        minTokensDraft: String,
        supportsContextCacheTTL: Bool,
        supportsContextCacheStrategy: Bool,
        supportsExplicitContextCacheMode: Bool,
        providerType: ProviderType?
    ) -> Result<ContextCacheControls?, ChatEditorDraftError> {
        var draft = draft

        switch applyContextCacheTTL(
            to: &draft,
            ttlPreset: ttlPreset,
            customTTLDraft: customTTLDraft,
            supportsContextCacheTTL: supportsContextCacheTTL
        ) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        switch applyContextCacheMinTokens(to: &draft, minTokensDraft: minTokensDraft) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        normalizeContextCacheTextFields(&draft)
        applyContextCacheCapabilityFallbacks(
            to: &draft,
            supportsContextCacheStrategy: supportsContextCacheStrategy,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode
        )
        removeProviderUnsupportedContextCacheFields(&draft, providerType: providerType)

        if draft.mode == .off {
            if providerType == .anthropic {
                return .success(ContextCacheControls(mode: .off))
            }
            return .success(nil)
        }

        return .success(draft)
    }

    static func applyContextCacheDraft(
        draft: ContextCacheControls,
        ttlPreset: ContextCacheTTLPreset,
        customTTLDraft: String,
        minTokensDraft: String,
        supportsContextCacheTTL: Bool,
        supportsContextCacheStrategy: Bool,
        supportsExplicitContextCacheMode: Bool,
        providerType: ProviderType?,
        controls: GenerationControls
    ) -> Result<AppliedContextCacheControls, ChatEditorDraftError> {
        applyContextCacheDraft(
            draft: draft,
            ttlPreset: ttlPreset,
            customTTLDraft: customTTLDraft,
            minTokensDraft: minTokensDraft,
            supportsContextCacheTTL: supportsContextCacheTTL,
            supportsContextCacheStrategy: supportsContextCacheStrategy,
            supportsExplicitContextCacheMode: supportsExplicitContextCacheMode,
            providerType: providerType
        ).map { contextCache in
            var controls = controls
            controls.contextCache = contextCache
            return AppliedContextCacheControls(
                controls: controls,
                contextCache: contextCache
            )
        }
    }
}

private extension ChatAuxiliaryControlSupport {
    static func applyContextCacheTTL(
        to draft: inout ContextCacheControls,
        ttlPreset: ContextCacheTTLPreset,
        customTTLDraft: String,
        supportsContextCacheTTL: Bool
    ) -> Result<Void, ChatEditorDraftError> {
        guard supportsContextCacheTTL else {
            draft.ttl = nil
            return .success(())
        }

        switch ttlPreset {
        case .providerDefault:
            draft.ttl = .providerDefault
        case .minutes5:
            draft.ttl = .minutes5
        case .hour1:
            draft.ttl = .hour1
        case .custom:
            guard let value = positiveContextCacheInteger(from: customTTLDraft) else {
                return .failure(.message("Custom TTL must be a positive integer (seconds)."))
            }
            draft.ttl = .customSeconds(value)
        }

        return .success(())
    }

    static func applyContextCacheMinTokens(
        to draft: inout ContextCacheControls,
        minTokensDraft: String
    ) -> Result<Void, ChatEditorDraftError> {
        if minTokensDraft.trimmedNonEmpty == nil {
            draft.minTokensThreshold = nil
        } else if let value = positiveContextCacheInteger(from: minTokensDraft) {
            draft.minTokensThreshold = value
        } else {
            return .failure(.message("Min tokens threshold must be a positive integer."))
        }

        return .success(())
    }

    static func normalizeContextCacheTextFields(_ draft: inout ContextCacheControls) {
        draft.cacheKey = normalizedContextCacheTextField(draft.cacheKey)
        draft.conversationID = normalizedContextCacheTextField(draft.conversationID)
        draft.cachedContentName = normalizedContextCacheTextField(draft.cachedContentName)
    }

    static func applyContextCacheCapabilityFallbacks(
        to draft: inout ContextCacheControls,
        supportsContextCacheStrategy: Bool,
        supportsExplicitContextCacheMode: Bool
    ) {
        if !supportsContextCacheStrategy {
            draft.strategy = nil
        } else if draft.strategy == nil {
            draft.strategy = .systemOnly
        }

        if !supportsExplicitContextCacheMode, draft.mode == .explicit {
            draft.mode = .implicit
        }
    }

    static func removeProviderUnsupportedContextCacheFields(
        _ draft: inout ContextCacheControls,
        providerType: ProviderType?
    ) {
        if providerType != .openai && providerType != .openaiWebSocket && providerType != .xai {
            draft.cacheKey = nil
        }
        if providerType != .xai {
            draft.minTokensThreshold = nil
            draft.conversationID = nil
        }
        if providerType != .gemini && providerType != .vertexai {
            draft.cachedContentName = nil
        }
    }
}
