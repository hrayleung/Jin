import Foundation

enum ThinkingBlockSupport {
    static func displayMode(rawValue: String?) -> ThinkingBlockDisplayMode {
        ThinkingBlockDisplayMode(rawValue: rawValue ?? "") ?? .expanded
    }

    static func initialExpansionForCompletedBlock(
        displayMode: ThinkingBlockDisplayMode
    ) -> Bool {
        displayMode.startsExpandedOnComplete
    }

    static func initialExpansionForStreamingBlock(
        displayMode: ThinkingBlockDisplayMode
    ) -> Bool {
        displayMode.startsExpandedDuringStreaming
    }

    static func shouldExpandAfterThinkingCompletion(
        isComplete: Bool,
        displayMode: ThinkingBlockDisplayMode
    ) -> Bool? {
        guard isComplete else { return nil }
        return displayMode == .collapseOnComplete ? false : nil
    }
}
