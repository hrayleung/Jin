import Foundation

struct MCPServerConfig: Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var isEnabled: Bool
    var runToolsAutomatically: Bool
    var isLongRunning: Bool
    var disabledTools: Set<String> = []
}
