import Foundation
import SwiftUI

/// Tracks in-flight streaming generations per conversation so they can continue
/// even when the user navigates away, and so the sidebar can show activity.
@MainActor
final class ConversationStreamingStore: ObservableObject {
    struct Session {
        let conversationID: UUID
        let state: StreamingMessageState
        var modelLabel: String?
        var task: Task<Void, Never>?
        var startedAt: Date
    }

    @Published private var sessionsByConversationID: [UUID: Session] = [:]

    func isStreaming(conversationID: UUID) -> Bool {
        sessionsByConversationID[conversationID] != nil
    }

    func streamingState(conversationID: UUID) -> StreamingMessageState? {
        sessionsByConversationID[conversationID]?.state
    }

    func streamingModelLabel(conversationID: UUID) -> String? {
        sessionsByConversationID[conversationID]?.modelLabel
    }

    /// Creates (or returns) a streaming session for a conversation.
    @discardableResult
    func beginSession(conversationID: UUID, modelLabel: String?) -> StreamingMessageState {
        if let existing = sessionsByConversationID[conversationID] {
            // Update label if we have a better one.
            if existing.modelLabel == nil, modelLabel != nil {
                var updated = existing
                updated.modelLabel = modelLabel
                sessionsByConversationID[conversationID] = updated
            }
            return existing.state
        }

        let state = StreamingMessageState()
        let session = Session(
            conversationID: conversationID,
            state: state,
            modelLabel: modelLabel,
            task: nil,
            startedAt: Date()
        )
        sessionsByConversationID[conversationID] = session
        return state
    }

    func attachTask(_ task: Task<Void, Never>, conversationID: UUID) {
        guard var existing = sessionsByConversationID[conversationID] else { return }
        existing.task = task
        sessionsByConversationID[conversationID] = existing
    }

    func cancel(conversationID: UUID) {
        sessionsByConversationID[conversationID]?.task?.cancel()
    }

    func endSession(conversationID: UUID) {
        sessionsByConversationID.removeValue(forKey: conversationID)
    }
}

