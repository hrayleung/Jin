import Foundation

/// A server-side tool execution reported by Codex App Server.
///
/// Each Codex turn may execute multiple tools (shell commands, file reads/writes,
/// code edits, etc.). The adapter yields these as `.codexToolActivity` stream events
/// so the UI can render a real-time execution timeline.
struct CodexToolActivity: Codable, Identifiable, Sendable {
    let id: String
    let toolName: String
    let status: CodexToolActivityStatus
    let arguments: [String: AnyCodable]
    let output: String?

    init(
        id: String,
        toolName: String,
        status: CodexToolActivityStatus,
        arguments: [String: AnyCodable] = [:],
        output: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.arguments = arguments
        self.output = output
    }

    /// Merge a newer update into this activity, preserving earlier fields when the
    /// newer update lacks them.
    func merged(with newer: CodexToolActivity) -> CodexToolActivity {
        CodexToolActivity(
            id: id,
            toolName: newer.toolName.isEmpty ? toolName : newer.toolName,
            status: newer.status,
            arguments: arguments.merging(newer.arguments) { _, new in new },
            output: newer.output ?? output
        )
    }
}
