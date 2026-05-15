import SwiftUI
import SwiftData

extension ChatView {

    func storedGenerationControls(for thread: ConversationModelThreadEntity) -> GenerationControls? {
        try? JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)
    }

    func mutateStoredGenerationControls(
        for thread: ConversationModelThreadEntity,
        _ mutate: (inout GenerationControls) -> Void
    ) {
        var controls = storedGenerationControls(for: thread) ?? GenerationControls()
        let previousManagedSessionID = controls.claudeManagedSessionID
        let previousManagedSessionModelID = controls.claudeManagedSessionModelID
        let previousManagedPendingResults = controls.claudeManagedPendingCustomToolResults
        mutate(&controls)
        guard controls.claudeManagedSessionID != previousManagedSessionID
            || controls.claudeManagedSessionModelID != previousManagedSessionModelID
            || controls.claudeManagedPendingCustomToolResults != previousManagedPendingResults else {
            return
        }

        do {
            thread.modelConfigData = try JSONEncoder().encode(controls)
            thread.updatedAt = Date()
            conversationEntity.updatedAt = max(conversationEntity.updatedAt, thread.updatedAt)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
