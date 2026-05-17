import Foundation
import SwiftUI

/// Tracks in-flight streaming generations per conversation so they can continue
/// even when the user navigates away, and so the sidebar can show activity.
///
/// Only **session lifecycle events** (begin / end) publish through
/// `objectWillChange`.  Internal mutations such as attaching a task or
/// updating a model label are silent, so views that merely check
/// `isStreaming` are not invalidated on every streaming token.
@MainActor
final class ConversationStreamingStore: ObservableObject {

    struct Session {
        let conversationID: UUID
        let state: StreamingMessageState
        var modelLabel: String?
        var modelID: String?
        var task: Task<Void, Never>?
        var startedAt: Date
    }

    /// Intentionally **not** `@Published` — we send `objectWillChange`
    /// manually so that only session creation / removal triggers view updates.
    private var sessionsByConversationID: [UUID: Session] = [:]

    /// Per-conversation streaming errors. Set by orchestrator failure paths via
    /// `recordError(...)` and cleared on the next `beginSession`.
    private var errorsByConversationID: [UUID: String] = [:]

    // MARK: - Queries (no side-effects)

    func isStreaming(conversationID: UUID) -> Bool {
        sessionsByConversationID[conversationID] != nil
    }

    func streamingState(conversationID: UUID) -> StreamingMessageState? {
        sessionsByConversationID[conversationID]?.state
    }

    func streamingModelLabel(conversationID: UUID) -> String? {
        sessionsByConversationID[conversationID]?.modelLabel
    }

    func streamingModelID(conversationID: UUID) -> String? {
        sessionsByConversationID[conversationID]?.modelID
    }

    /// Returns the most recent unrecovered streaming error, or nil.
    /// Cleared on the next `beginSession`.
    func error(conversationID: UUID) -> String? {
        errorsByConversationID[conversationID]
    }

    // MARK: - Lifecycle (publishes objectWillChange)

    /// Creates (or returns) a streaming session for a conversation.
    @discardableResult
    func beginSession(conversationID: UUID, modelLabel: String?, modelID: String? = nil) -> StreamingMessageState {
        if errorsByConversationID[conversationID] != nil {
            clearError(conversationID: conversationID)
        }

        if let existing = sessionsByConversationID[conversationID] {
            if (existing.modelLabel == nil && modelLabel != nil) || (existing.modelID == nil && modelID != nil) {
                var updated = existing
                if updated.modelLabel == nil {
                    updated.modelLabel = modelLabel
                }
                if updated.modelID == nil {
                    updated.modelID = modelID
                }
                sessionsByConversationID[conversationID] = updated
            }
            return existing.state
        }

        let createdSession = Session(
            conversationID: conversationID,
            state: StreamingMessageState(),
            modelLabel: modelLabel,
            modelID: modelID,
            task: nil,
            startedAt: Date()
        )
        objectWillChange.send()
        sessionsByConversationID[conversationID] = createdSession
        return createdSession.state
    }

    func endSession(conversationID: UUID) {
        guard sessionsByConversationID[conversationID] != nil else { return }
        objectWillChange.send()
        sessionsByConversationID.removeValue(forKey: conversationID)
    }

    // MARK: - Silent mutations (no publish)

    func attachTask(_ task: Task<Void, Never>, conversationID: UUID) {
        guard var session = sessionsByConversationID[conversationID] else { return }
        session.task = task
        sessionsByConversationID[conversationID] = session
    }

    func cancel(conversationID: UUID) {
        sessionsByConversationID[conversationID]?.task?.cancel()
    }

    /// Records a streaming error so the UI can surface it.
    func recordError(conversationID: UUID, message: String) {
        objectWillChange.send()
        errorsByConversationID[conversationID] = message
    }

    /// Clears any recorded error for `conversationID`.
    func clearError(conversationID: UUID) {
        guard errorsByConversationID[conversationID] != nil else { return }
        objectWillChange.send()
        errorsByConversationID.removeValue(forKey: conversationID)
    }
}
