import SwiftUI
import SwiftData

// MARK: - Codex Thread Persistence

extension ChatView {

    func injectCodexThreadPersistence(into controls: inout GenerationControls, from thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else {
            controls.codexResumeThreadID = nil
            controls.codexPendingRollbackTurns = 0
            return
        }

        let storedControls = storedGenerationControls(for: thread) ?? GenerationControls()
        controls.codexResumeThreadID = storedControls.codexResumeThreadID
        controls.codexPendingRollbackTurns = storedControls.codexPendingRollbackTurns
    }

    func persistCodexThreadState(_ state: CodexThreadState, forLocalThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }

        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.codexResumeThreadID = state.remoteThreadID
            storedControls.codexPendingRollbackTurns = 0
        }
    }

    func clearCodexThreadPersistence(for thread: ConversationModelThreadEntity) {
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }
        mutateStoredGenerationControls(for: thread) { storedControls in
            storedControls.codexResumeThreadID = nil
            storedControls.codexPendingRollbackTurns = 0
        }
    }

    func invalidateCodexThreadPersistence(forThreadID threadID: UUID) {
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }
        clearCodexThreadPersistence(for: thread)
    }

    func recordCodexThreadHistoryMutation(forThreadID threadID: UUID, removedMessages: [MessageEntity]) {
        guard !removedMessages.isEmpty else { return }
        guard let thread = sortedModelThreads.first(where: { $0.id == threadID }) else { return }
        guard providerType(forProviderID: thread.providerID) == .codexAppServer else { return }

        let storedControls = storedGenerationControls(for: thread) ?? GenerationControls()
        guard storedControls.codexResumeThreadID != nil else { return }

        if removedMessages.contains(where: { $0.turnID == nil }) {
            clearCodexThreadPersistence(for: thread)
            return
        }

        let removedTurnCount = Set(removedMessages.compactMap(\.turnID)).count
        guard removedTurnCount > 0 else { return }
        mutateStoredGenerationControls(for: thread) { controls in
            controls.codexPendingRollbackTurns += removedTurnCount
        }
    }

    func storedGenerationControls(for thread: ConversationModelThreadEntity) -> GenerationControls? {
        try? JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
    }

    func mutateStoredGenerationControls(
        for thread: ConversationModelThreadEntity,
        _ mutate: (inout GenerationControls) -> Void
    ) {
        var controls = storedGenerationControls(for: thread) ?? GenerationControls()
        let previousResumeThreadID = controls.codexResumeThreadID
        let previousRollbackTurns = controls.codexPendingRollbackTurns
        let previousManagedSessionID = controls.claudeManagedSessionID
        let previousManagedSessionModelID = controls.claudeManagedSessionModelID
        let previousManagedPendingResults = controls.claudeManagedPendingCustomToolResults
        mutate(&controls)
        guard controls.codexResumeThreadID != previousResumeThreadID
            || controls.codexPendingRollbackTurns != previousRollbackTurns
            || controls.claudeManagedSessionID != previousManagedSessionID
            || controls.claudeManagedSessionModelID != previousManagedSessionModelID
            || controls.claudeManagedPendingCustomToolResults != previousManagedPendingResults else {
            return
        }

        do {
            thread.modelConfigData = try JSONEncoder().encode(controls)
            thread.updatedAt = Date()
            if conversationEntity.activeThreadID == thread.id {
                conversationEntity.modelConfigData = thread.modelConfigData
            }
            conversationEntity.updatedAt = max(conversationEntity.updatedAt, thread.updatedAt)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
