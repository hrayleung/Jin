import Foundation

extension ChatStreamingOrchestrator {
    enum RequestControlStreamUpdate {
        case claudeManagedSession(ClaudeManagedAgentSessionState)
        case claudeManagedCustomToolResults([ClaudeManagedAgentPendingToolResult])
    }

    static func persistRequestControlStreamUpdate(
        _ update: RequestControlStreamUpdate,
        callbacks: SessionCallbacks
    ) async {
        await MainActor.run {
            switch update {
            case .claudeManagedSession(let state):
                callbacks.persistClaudeManagedSessionState(state)
            case .claudeManagedCustomToolResults(let results):
                callbacks.persistClaudeManagedPendingToolResults(results)
            }
        }
    }

    static func applyRequestControlStreamUpdate(
        _ update: RequestControlStreamUpdate,
        requestControls: inout GenerationControls,
        callbacks: SessionCallbacks
    ) async {
        requestControls.applyChatStreamingUpdate(update)
        await persistRequestControlStreamUpdate(
            update,
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
