import Foundation

extension ChatAuxiliaryControlSupport {
    static func prepareContextCacheEditorDraft(
        current: ContextCacheControls?,
        providerType: ProviderType?,
        supportsContextCacheTTL: Bool
    ) -> PreparedContextCacheEditorDraft {
        let defaultMode: ContextCacheMode = (providerType == .anthropic) ? .implicit : .off
        let draft = current ?? ContextCacheControls(mode: defaultMode)
        let ttlPreset = ContextCacheTTLPreset.from(ttl: draft.ttl)
        let customTTLDraft: String
        if case .customSeconds(let seconds) = draft.ttl {
            customTTLDraft = "\(seconds)"
        } else {
            customTTLDraft = ""
        }

        return PreparedContextCacheEditorDraft(
            draft: draft,
            ttlPreset: ttlPreset,
            customTTLDraft: customTTLDraft,
            minTokensDraft: draft.minTokensThreshold.map(String.init) ?? "",
            advancedExpanded: shouldExpandContextCacheAdvancedOptions(
                for: draft,
                providerType: providerType,
                supportsContextCacheTTL: supportsContextCacheTTL
            )
        )
    }

    static func shouldExpandContextCacheAdvancedOptions(
        for draft: ContextCacheControls,
        providerType: ProviderType?,
        supportsContextCacheTTL: Bool
    ) -> Bool {
        guard draft.mode != .off else { return false }

        if supportsContextCacheTTL,
           let ttl = draft.ttl,
           ttl != .providerDefault {
            return true
        }

        if providerType == .xai {
            if normalizedContextCacheTextField(draft.cacheKey) != nil {
                return true
            }
        }

        if providerType == .xai,
           normalizedContextCacheTextField(draft.conversationID) != nil {
            return true
        }

        return false
    }
}
