import Foundation

enum AgentApprovalPresentationSupport {
    static func requestDescription(for kind: AgentApprovalKind) -> String {
        switch kind {
        case .shellCommand:
            return "The agent wants to execute a shell command that is not in the allowed command list."
        case .fileWrite:
            return "The agent wants to create or overwrite a file."
        case .fileEdit:
            return "The agent wants to modify an existing file."
        }
    }
}
