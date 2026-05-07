import Foundation

extension ChatAuxiliaryControlSupport {
    static func isContextCacheDraftValid(
        contextCacheDraft: ContextCacheControls,
        ttlPreset: ContextCacheTTLPreset,
        customTTLDraft: String,
        minTokensDraft: String,
        supportsExplicitContextCacheMode: Bool
    ) -> Bool {
        if ttlPreset == .custom {
            guard positiveContextCacheInteger(from: customTTLDraft) != nil else { return false }
        }

        if minTokensDraft.trimmedNonEmpty != nil {
            guard positiveContextCacheInteger(from: minTokensDraft) != nil else { return false }
        }

        if supportsExplicitContextCacheMode, contextCacheDraft.mode == .explicit {
            return normalizedContextCacheTextField(contextCacheDraft.cachedContentName) != nil
        }

        return true
    }
}
