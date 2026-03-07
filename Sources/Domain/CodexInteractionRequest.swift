import Foundation

enum CodexApprovalChoice: String, CaseIterable, Sendable {
    case accept
    case acceptForSession
    case decline
    case cancel

    var displayName: String {
        switch self {
        case .accept:
            return "Allow Once"
        case .acceptForSession:
            return "Allow for Session"
        case .decline:
            return "Decline"
        case .cancel:
            return "Cancel Turn"
        }
    }
}

struct CodexCommandActionSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?

    init(id: String = UUID().uuidString, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

struct CodexFileChangeSummary: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let changeType: String

    init(path: String, changeType: String) {
        self.id = path
        self.path = path
        self.changeType = changeType
    }
}

struct CodexCommandApprovalRequest: Sendable {
    let command: String?
    let cwd: String?
    let reason: String?
    let actionSummaries: [CodexCommandActionSummary]
}

struct CodexFileChangeApprovalRequest: Sendable {
    let reason: String?
    let grantRoot: String?
    let fileChanges: [CodexFileChangeSummary]
}

struct CodexUserInputOption: Hashable, Sendable {
    let label: String
    let detail: String
}

struct CodexUserInputQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let header: String
    let prompt: String
    let isOtherAllowed: Bool
    let isSecret: Bool
    let options: [CodexUserInputOption]
}

struct CodexUserInputRequest: Sendable {
    let questions: [CodexUserInputQuestion]
}

enum CodexInteractionKind: Sendable {
    case commandApproval(CodexCommandApprovalRequest)
    case fileChangeApproval(CodexFileChangeApprovalRequest)
    case userInput(CodexUserInputRequest)
}

enum CodexInteractionResponse: Sendable {
    case approval(CodexApprovalChoice)
    case userInput([String: [String]])
    case cancelled(message: String?)
}

actor CodexInteractionResponseChannel {
    private var continuation: CheckedContinuation<CodexInteractionResponse, Never>?
    private var buffered: CodexInteractionResponse?

    func wait() async -> CodexInteractionResponse {
        if let buffered {
            self.buffered = nil
            return buffered
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ response: CodexInteractionResponse) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: response)
        } else {
            buffered = response
        }
    }
}

final class CodexInteractionRequest: Identifiable, @unchecked Sendable {
    let id = UUID()
    let method: String
    let threadID: String?
    let turnID: String?
    let itemID: String?
    let kind: CodexInteractionKind

    private let channel = CodexInteractionResponseChannel()

    init(
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        kind: CodexInteractionKind
    ) {
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .commandApproval:
            return "Codex Wants to Run a Command"
        case .fileChangeApproval:
            return "Codex Wants to Change Files"
        case .userInput:
            return "Codex Needs Your Input"
        }
    }

    var subtitle: String? {
        switch kind {
        case .commandApproval(let request):
            return request.reason
        case .fileChangeApproval(let request):
            return request.reason
        case .userInput:
            return nil
        }
    }

    func waitForResponse() async -> CodexInteractionResponse {
        await channel.wait()
    }

    func resolve(_ response: CodexInteractionResponse) async {
        await channel.resolve(response)
    }
}
