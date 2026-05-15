import Foundation

extension ChatStreamingOrchestrator {
    enum RequestControlStreamUpdate {
        case claudeManagedSession(ClaudeManagedAgentSessionState)
        case claudeManagedCustomToolResults([ClaudeManagedAgentPendingToolResult])
    }

    static func persistRequestControlStreamUpdate(
        _ update: RequestControlStreamUpdate,
        threadID: UUID,
        callbacks: SessionCallbacks
    ) async {
        await MainActor.run {
            switch update {
            case .claudeManagedSession(let state):
                callbacks.persistClaudeManagedSessionState(state, threadID)
            case .claudeManagedCustomToolResults(let results):
                callbacks.persistClaudeManagedPendingToolResults(results, threadID)
            }
        }
    }

    static func applyRequestControlStreamUpdate(
        _ update: RequestControlStreamUpdate,
        requestControls: inout GenerationControls,
        threadID: UUID,
        callbacks: SessionCallbacks
    ) async {
        requestControls.applyChatStreamingUpdate(update)
        await persistRequestControlStreamUpdate(
            update,
            threadID: threadID,
            callbacks: callbacks
        )
    }
}

extension GenerationControls {
    mutating func applyChatStreamingUpdate(
        _ update: ChatStreamingOrchestrator.RequestControlStreamUpdate
    ) {
        switch update {
        case .claudeManagedSession(let state):
            claudeManagedSessionID = state.remoteSessionID
            claudeManagedSessionModelID = state.remoteModelID
        case .claudeManagedCustomToolResults(let results):
            claudeManagedPendingCustomToolResults = results
        }
    }
}
