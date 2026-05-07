import Foundation

extension CodexToolTimelineSupport {
    static func displayMode(rawValue: String?) -> CodexToolDisplayMode {
        CodexToolDisplayMode(rawValue: rawValue ?? "") ?? .expanded
    }

    static func initialExpansion(
        isStreaming: Bool,
        displayMode: CodexToolDisplayMode
    ) -> Bool {
        if isStreaming {
            return displayMode.startsExpandedDuringStreaming
        }
        return displayMode.startsExpandedOnComplete
    }

    static func shouldExpandAfterStreamingChange(
        isStreaming: Bool,
        displayMode: CodexToolDisplayMode
    ) -> Bool? {
        if isStreaming {
            return displayMode.startsExpandedDuringStreaming ? true : nil
        }
        return displayMode == .collapseOnComplete ? false : nil
    }
}
