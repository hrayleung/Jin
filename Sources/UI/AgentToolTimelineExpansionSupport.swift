import Foundation

extension AgentToolTimelineSupport {
    static func displayMode(rawValue: String?) -> AgentToolDisplayMode {
        AgentToolDisplayMode(rawValue: rawValue ?? "") ?? .expanded
    }

    static func initialExpansion(
        isStreaming: Bool,
        displayMode: AgentToolDisplayMode
    ) -> Bool {
        if isStreaming {
            return displayMode.startsExpandedDuringStreaming
        }
        return displayMode.startsExpandedOnComplete
    }

    static func shouldExpandAfterStreamingChange(
        isStreaming: Bool,
        displayMode: AgentToolDisplayMode
    ) -> Bool? {
        if isStreaming {
            return displayMode.startsExpandedDuringStreaming ? true : nil
        }
        return displayMode == .collapseOnComplete ? false : nil
    }
}
