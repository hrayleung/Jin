import Foundation

/// A type that exposes the minimal fields needed by the shared message-processing
/// algorithms: a stable identity UUID and a role raw-value string.
protocol MessageRoleIdentifiable {
    var id: UUID { get }
    var role: String { get }
    var toolResultsData: Data? { get }
}

extension MessageEntity: MessageRoleIdentifiable {}
extension PersistedMessageSnapshot: MessageRoleIdentifiable {}

// MARK: - Shared algorithms

enum MessageRoleIdentifiableSupport {

    /// Returns the subset of `orderedMessages` that should be deleted when
    /// regenerating a response after the given user message:
    /// all consecutive assistant/tool messages that follow it (stopping at the
    /// next user message).  Returns `nil` if the anchor is not found or there
    /// is nothing to delete.
    static func messagesToDeleteForResponse<T: MessageRoleIdentifiable>(
        afterUserMessage message: T,
        orderedMessages: [T]
    ) -> [T]? {
        guard let index = orderedMessages.firstIndex(where: { $0.id == message.id }) else { return nil }
        let startIndex = index + 1
        guard startIndex < orderedMessages.count else { return nil }

        var result: [T] = []
        for i in startIndex..<orderedMessages.count {
            let msg = orderedMessages[i]
            if msg.role == MessageRole.user.rawValue { break }
            if msg.role == MessageRole.assistant.rawValue || msg.role == MessageRole.tool.rawValue {
                result.append(msg)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Builds a `toolCallID → ToolResult` index from all tool-role messages.
    /// Pass `checkCancellation: true` from async contexts that need cooperative
    /// cancellation (e.g. off-main-thread snapshot processing).
    static func toolResultsByToolCallID<T: MessageRoleIdentifiable>(
        in messages: [T],
        checkCancellation: Bool = false
    ) -> [String: ToolResult] {
        var results: [String: ToolResult] = [:]
        results.reserveCapacity(8)

        let decoder = JSONDecoder()
        for message in messages where message.role == MessageRole.tool.rawValue {
            if checkCancellation && Task.isCancelled { break }
            guard let toolResults = decoder.decodeOptional([ToolResult].self, from: message.toolResultsData) else {
                continue
            }
            for result in toolResults {
                results[result.toolCallID] = result
            }
        }
        return results
    }
}
