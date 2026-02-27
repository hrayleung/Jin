import Foundation
import SwiftUI

/// Tracks in-flight streaming generations per conversation so they can continue
/// even when the user navigates away, and so the sidebar can show activity.
@MainActor
final class ConversationStreamingStore: ObservableObject {
    struct Session {
        let conversationID: UUID
        let threadID: UUID
        let state: StreamingMessageState
        var modelLabel: String?
        var task: Task<Void, Never>?
        var startedAt: Date
    }

    @Published private var sessionsByConversationID: [UUID: [UUID: Session]] = [:]

    func isStreaming(conversationID: UUID) -> Bool {
        !(sessionsByConversationID[conversationID] ?? [:]).isEmpty
    }

    func isStreaming(conversationID: UUID, threadID: UUID) -> Bool {
        sessionsByConversationID[conversationID]?[threadID] != nil
    }

    func streamingState(conversationID: UUID) -> StreamingMessageState? {
        sessionsByConversationID[conversationID]?
            .values
            .sorted(by: { $0.startedAt < $1.startedAt })
            .last?
            .state
    }

    func streamingState(conversationID: UUID, threadID: UUID) -> StreamingMessageState? {
        sessionsByConversationID[conversationID]?[threadID]?.state
    }

    func streamingModelLabel(conversationID: UUID) -> String? {
        sessionsByConversationID[conversationID]?
            .values
            .sorted(by: { $0.startedAt < $1.startedAt })
            .last?
            .modelLabel
    }

    func streamingModelLabel(conversationID: UUID, threadID: UUID) -> String? {
        sessionsByConversationID[conversationID]?[threadID]?.modelLabel
    }

    /// Creates (or returns) a streaming session for a conversation thread.
    @discardableResult
    func beginSession(conversationID: UUID, threadID: UUID, modelLabel: String?) -> StreamingMessageState {
        if let existing = sessionsByConversationID[conversationID]?[threadID] {
            // Update label if we have a better one.
            if existing.modelLabel == nil, modelLabel != nil {
                var updated = existing
                updated.modelLabel = modelLabel
                sessionsByConversationID[conversationID]?[threadID] = updated
            }
            return existing.state
        }

        let state = StreamingMessageState()
        let session = Session(
            conversationID: conversationID,
            threadID: threadID,
            state: state,
            modelLabel: modelLabel,
            task: nil,
            startedAt: Date()
        )
        var sessions = sessionsByConversationID[conversationID] ?? [:]
        sessions[threadID] = session
        sessionsByConversationID[conversationID] = sessions
        return state
    }

    /// Backward-compatible helper for single-thread callers.
    @discardableResult
    func beginSession(conversationID: UUID, modelLabel: String?) -> StreamingMessageState {
        beginSession(conversationID: conversationID, threadID: conversationID, modelLabel: modelLabel)
    }

    func attachTask(_ task: Task<Void, Never>, conversationID: UUID, threadID: UUID) {
        guard var existing = sessionsByConversationID[conversationID]?[threadID] else { return }
        existing.task = task
        sessionsByConversationID[conversationID]?[threadID] = existing
    }

    func attachTask(_ task: Task<Void, Never>, conversationID: UUID) {
        attachTask(task, conversationID: conversationID, threadID: conversationID)
    }

    func cancel(conversationID: UUID) {
        let sessions = sessionsByConversationID[conversationID] ?? [:]
        for session in sessions.values {
            session.task?.cancel()
        }
    }

    func cancel(conversationID: UUID, threadID: UUID) {
        sessionsByConversationID[conversationID]?[threadID]?.task?.cancel()
    }

    func endSession(conversationID: UUID) {
        sessionsByConversationID.removeValue(forKey: conversationID)
    }

    func endSession(conversationID: UUID, threadID: UUID) {
        guard var sessions = sessionsByConversationID[conversationID] else { return }
        sessions.removeValue(forKey: threadID)
        if sessions.isEmpty {
            sessionsByConversationID.removeValue(forKey: conversationID)
        } else {
            sessionsByConversationID[conversationID] = sessions
        }
    }
}
