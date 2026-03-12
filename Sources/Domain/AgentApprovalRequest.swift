import Foundation

enum AgentApprovalKind: Sendable {
    case shellCommand(command: String, cwd: String?)
    case fileWrite(path: String, preview: String)
    case fileEdit(path: String, oldText: String, newText: String)
}

enum AgentApprovalChoice: String, CaseIterable, Sendable {
    case allow
    case allowForSession
    case deny
    case cancel

    var displayName: String {
        switch self {
        case .allow:
            return "Allow Once"
        case .allowForSession:
            return "Allow for Session"
        case .deny:
            return "Deny"
        case .cancel:
            return "Cancel Turn"
        }
    }
}

actor AgentApprovalResponseChannel {
    private var continuation: CheckedContinuation<AgentApprovalChoice, Never>?
    private var buffered: AgentApprovalChoice?

    func wait() async -> AgentApprovalChoice {
        if let buffered {
            self.buffered = nil
            return buffered
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ choice: AgentApprovalChoice) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: choice)
        } else {
            buffered = choice
        }
    }
}

final class AgentApprovalRequest: Identifiable, @unchecked Sendable {
    let id = UUID()
    let kind: AgentApprovalKind

    private let channel = AgentApprovalResponseChannel()

    init(kind: AgentApprovalKind) {
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .shellCommand:
            return "Agent Wants to Run a Command"
        case .fileWrite:
            return "Agent Wants to Write a File"
        case .fileEdit:
            return "Agent Wants to Edit a File"
        }
    }

    var subtitle: String? {
        switch kind {
        case .shellCommand(let command, _):
            return command
        case .fileWrite(let path, _):
            return path
        case .fileEdit(let path, _, _):
            return path
        }
    }

    func waitForResponse() async -> AgentApprovalChoice {
        await channel.wait()
    }

    func resolve(_ choice: AgentApprovalChoice) async {
        await channel.resolve(choice)
    }
}
