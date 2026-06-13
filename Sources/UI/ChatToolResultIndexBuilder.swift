import Foundation

enum ChatToolResultIndexBuilder {
    static func toolResultsByToolCallID(in messageEntities: [MessageEntity]) -> [String: ToolResult] {
        MessageRoleIdentifiableSupport.toolResultsByToolCallID(in: messageEntities)
    }

    static func toolResultsByToolCallID(in messageSnapshots: [PersistedMessageSnapshot]) -> [String: ToolResult] {
        MessageRoleIdentifiableSupport.toolResultsByToolCallID(in: messageSnapshots, checkCancellation: true)
    }
}
