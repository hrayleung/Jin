import Foundation

enum ManagedAgentApprovalChoice: String, CaseIterable, Sendable {
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

struct ManagedAgentCommandActionSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?

    init(id: String = UUID().uuidString, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

struct ManagedAgentFileChangeSummary: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let changeType: String

    init(path: String, changeType: String) {
        self.id = path
        self.path = path
        self.changeType = changeType
    }
}

struct ManagedAgentCommandApprovalRequest: Sendable {
    let command: String?
    let cwd: String?
    let reason: String?
    let actionSummaries: [ManagedAgentCommandActionSummary]
}

struct ManagedAgentFileChangeApprovalRequest: Sendable {
    let reason: String?
    let grantRoot: String?
    let fileChanges: [ManagedAgentFileChangeSummary]
}

struct ManagedAgentUserInputOption: Hashable, Sendable {
    let label: String
    let detail: String
}

struct ManagedAgentUserInputQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let header: String
    let prompt: String
    let isOtherAllowed: Bool
    let isSecret: Bool
    let options: [ManagedAgentUserInputOption]
}

struct ManagedAgentUserInputRequest: Sendable {
    let questions: [ManagedAgentUserInputQuestion]
}

enum ManagedAgentInteractionKind: Sendable {
    case commandApproval(ManagedAgentCommandApprovalRequest)
    case fileChangeApproval(ManagedAgentFileChangeApprovalRequest)
    case userInput(ManagedAgentUserInputRequest)
}

enum ManagedAgentInteractionResponse: Sendable {
    case approval(ManagedAgentApprovalChoice)
    case userInput([String: [String]])
    case cancelled(message: String?)
}

actor ManagedAgentInteractionResponseChannel {
    private var continuation: CheckedContinuation<ManagedAgentInteractionResponse, Never>?
    private var buffered: ManagedAgentInteractionResponse?

    func wait() async -> ManagedAgentInteractionResponse {
        if let buffered {
            self.buffered = nil
            return buffered
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ response: ManagedAgentInteractionResponse) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: response)
        } else {
            buffered = response
        }
    }
}

final class ManagedAgentInteractionRequest: Identifiable, @unchecked Sendable {
    let id = UUID()
    let method: String
    let threadID: String?
    let turnID: String?
    let itemID: String?
    let kind: ManagedAgentInteractionKind
    let providerContext: [String: String]

    private let channel = ManagedAgentInteractionResponseChannel()

    init(
        method: String,
        threadID: String?,
        turnID: String?,
        itemID: String?,
        kind: ManagedAgentInteractionKind,
        providerContext: [String: String] = [:]
    ) {
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.kind = kind
        self.providerContext = providerContext
    }

    var title: String {
        switch kind {
        case .commandApproval:
            return "Claude Agent Wants to Use a Tool"
        case .fileChangeApproval:
            return "Claude Agent Wants to Change Files"
        case .userInput:
            return "Claude Agent Needs Your Input"
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

    func providerContextValue(for key: String) -> String? {
        providerContext[key]
    }

    func waitForResponse() async -> ManagedAgentInteractionResponse {
        await channel.wait()
    }

    func resolve(_ response: ManagedAgentInteractionResponse) async {
        await channel.resolve(response)
    }
}
