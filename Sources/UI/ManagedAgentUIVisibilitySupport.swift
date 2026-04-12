import Foundation

enum ManagedAgentUIVisibilitySupport {
    static func hidesInternalUI(providerType: ProviderType?) -> Bool {
        providerType == .claudeManagedAgents
    }

    static func isVisibleContentPart(_ part: RenderedContentPart, providerType: ProviderType?) -> Bool {
        switch part {
        case .thinking:
            return !hidesInternalUI(providerType: providerType)
        case .redactedThinking:
            return false
        case .text, .quote, .image, .video, .file, .audio:
            return true
        }
    }

    static func isVisibleRenderedBlock(_ block: RenderedMessageBlock, providerType: ProviderType?) -> Bool {
        switch block {
        case .content(_, let part):
            return isVisibleContentPart(part, providerType: providerType)
        case .artifact:
            return true
        }
    }
}
