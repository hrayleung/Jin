import Foundation

struct MCPServerConfig: Identifiable, Sendable {
    let id: String
    var name: String
    var command: String
    var args: [String]
    var env: [String: String]
    var isEnabled: Bool
    var runToolsAutomatically: Bool
    var isLongRunning: Bool
}

