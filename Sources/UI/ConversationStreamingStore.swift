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

    /// True when a generation task is already running for this conversation.
    /// An armed-but-idle session (placeholder painted before the network task
    /// starts) returns false so `startStreamingResponse` can attach work to it.
    func hasActiveStreamingTask(conversationID: UUID) -> Bool {
        sessionsByConversationID[conversationID]?.task != nil
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
            // Prefer fresher labels from the real startStreaming setup over the
            // provisional ones stamped when the placeholder was armed on send.
            var updated = existing
            var changed = false
            if let modelLabel, updated.modelLabel != modelLabel {
                updated.modelLabel = modelLabel
                changed = true
            }
            if let modelID, updated.modelID != modelID {
                updated.modelID = modelID
                changed = true
            }
            if changed {
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
        guard let session = sessionsByConversationID[conversationID] else { return }
        if let task = session.task {
            // Live generation: cooperative cancel; `onSessionEnd` tears the
            // session down once the orchestrator observes CancellationError.
            task.cancel()
        } else {
            // Armed placeholder with no task yet (send paint → yield window).
            // Nothing is running to observe cancel, so end immediately or the
            // conversation stays "busy" with an empty streaming row forever.
            endSession(conversationID: conversationID)
        }
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
