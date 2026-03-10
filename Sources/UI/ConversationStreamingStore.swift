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
    private typealias SessionMap = [UUID: Session]

    struct Session {
        let conversationID: UUID
        let threadID: UUID
        let state: StreamingMessageState
        var modelLabel: String?
        var task: Task<Void, Never>?
        var startedAt: Date
    }

    /// Intentionally **not** `@Published` — we send `objectWillChange`
    /// manually so that only session creation / removal triggers view updates.
    private var sessionsByConversationID: [UUID: SessionMap] = [:]

    // MARK: - Queries (no side-effects)

    func isStreaming(conversationID: UUID) -> Bool {
        !sessions(for: conversationID).isEmpty
    }

    func isStreaming(conversationID: UUID, threadID: UUID) -> Bool {
        session(conversationID: conversationID, threadID: threadID) != nil
    }

    func streamingState(conversationID: UUID) -> StreamingMessageState? {
        latestSession(in: conversationID)?.state
    }

    func streamingState(conversationID: UUID, threadID: UUID) -> StreamingMessageState? {
        session(conversationID: conversationID, threadID: threadID)?.state
    }

    func streamingModelLabel(conversationID: UUID) -> String? {
        latestSession(in: conversationID)?.modelLabel
    }

    func streamingModelLabel(conversationID: UUID, threadID: UUID) -> String? {
        session(conversationID: conversationID, threadID: threadID)?.modelLabel
    }

    // MARK: - Lifecycle (publishes objectWillChange)

    /// Creates (or returns) a streaming session for a conversation thread.
    @discardableResult
    func beginSession(conversationID: UUID, threadID: UUID, modelLabel: String?) -> StreamingMessageState {
        if let existing = session(conversationID: conversationID, threadID: threadID) {
            // Update label if we have a better one — silent, no publish.
            if existing.modelLabel == nil, modelLabel != nil {
                updateSession(conversationID: conversationID, threadID: threadID) { session in
                    session.modelLabel = modelLabel
                }
            }
            return existing.state
        }

        let createdSession = Session(
            conversationID: conversationID,
            threadID: threadID,
            state: StreamingMessageState(),
            modelLabel: modelLabel,
            task: nil,
            startedAt: Date()
        )
        objectWillChange.send()
        storeSession(createdSession)
        return createdSession.state
    }

    /// Backward-compatible helper for single-thread callers.
    @discardableResult
    func beginSession(conversationID: UUID, modelLabel: String?) -> StreamingMessageState {
        beginSession(conversationID: conversationID, threadID: conversationID, modelLabel: modelLabel)
    }

    func endSession(conversationID: UUID) {
        guard sessionsByConversationID[conversationID] != nil else { return }
        objectWillChange.send()
        sessionsByConversationID.removeValue(forKey: conversationID)
    }

    func endSession(conversationID: UUID, threadID: UUID) {
        guard session(conversationID: conversationID, threadID: threadID) != nil else { return }
        objectWillChange.send()
        removeSession(conversationID: conversationID, threadID: threadID)
    }

    // MARK: - Silent mutations (no publish)

    func attachTask(_ task: Task<Void, Never>, conversationID: UUID, threadID: UUID) {
        updateSession(conversationID: conversationID, threadID: threadID) { session in
            session.task = task
        }
    }

    func attachTask(_ task: Task<Void, Never>, conversationID: UUID) {
        attachTask(task, conversationID: conversationID, threadID: conversationID)
    }

    func cancel(conversationID: UUID) {
        for session in sessions(for: conversationID).values {
            session.task?.cancel()
        }
    }

    func cancel(conversationID: UUID, threadID: UUID) {
        session(conversationID: conversationID, threadID: threadID)?.task?.cancel()
    }

    // MARK: - Private helpers

    private func sessions(for conversationID: UUID) -> SessionMap {
        sessionsByConversationID[conversationID] ?? [:]
    }

    private func session(conversationID: UUID, threadID: UUID) -> Session? {
        sessionsByConversationID[conversationID]?[threadID]
    }

    private func latestSession(in conversationID: UUID) -> Session? {
        sessions(for: conversationID).values.max(by: { $0.startedAt < $1.startedAt })
    }

    private func updateSession(
        conversationID: UUID,
        threadID: UUID,
        mutate: (inout Session) -> Void
    ) {
        guard var existing = session(conversationID: conversationID, threadID: threadID) else { return }
        mutate(&existing)
        storeSession(existing)
    }

    private func storeSession(_ session: Session) {
        var conversationSessions = sessions(for: session.conversationID)
        conversationSessions[session.threadID] = session
        sessionsByConversationID[session.conversationID] = conversationSessions
    }

    private func removeSession(conversationID: UUID, threadID: UUID) {
        guard var conversationSessions = sessionsByConversationID[conversationID] else { return }
        conversationSessions.removeValue(forKey: threadID)
        if conversationSessions.isEmpty {
            sessionsByConversationID.removeValue(forKey: conversationID)
        } else {
            sessionsByConversationID[conversationID] = conversationSessions
        }
    }
}
