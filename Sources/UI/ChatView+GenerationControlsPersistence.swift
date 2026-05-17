import SwiftUI
import SwiftData

extension ChatView {

    func storedGenerationControls() -> GenerationControls? {
        try? JSONDecoder().decode(GenerationControls.self, from: conversationEntity.modelConfigData)
    }

    func mutateStoredGenerationControls(
        _ mutate: (inout GenerationControls) -> Void
    ) {
        var controls = storedGenerationControls() ?? GenerationControls()
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
            conversationEntity.modelConfigData = try JSONEncoder().encode(controls)
            conversationEntity.updatedAt = Date()
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
