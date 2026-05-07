import Foundation

struct PreparedContextCacheEditorDraft {
    let draft: ContextCacheControls
    let ttlPreset: ContextCacheTTLPreset
    let customTTLDraft: String
    let minTokensDraft: String
    let advancedExpanded: Bool
}

struct AppliedContextCacheControls {
    let controls: GenerationControls
    let contextCache: ContextCacheControls?
}
