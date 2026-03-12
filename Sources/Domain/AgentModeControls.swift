import Foundation

/// Controls for agent mode — local shell execution, file operations, and codebase search.
struct AgentModeControls: Codable, Sendable {
    var enabled: Bool = false
    var workingDirectory: String?
    var allowedCommandPrefixes: [String] = []
    var autoApproveFileReads: Bool = true
    var bypassPermissions: Bool = false
    var enabledTools: AgentEnabledTools = AgentEnabledTools()
    var commandTimeoutSeconds: Int = 120
    var maxOutputBytes: Int = 102_400 // 100KB truncation
}

/// Per-tool enable/disable toggles for agent mode.
struct AgentEnabledTools: Codable, Sendable {
    var shellExecute: Bool = true
    var fileRead: Bool = true
    var fileWrite: Bool = true
    var fileEdit: Bool = true
    var globSearch: Bool = true
    var grepSearch: Bool = true
}
