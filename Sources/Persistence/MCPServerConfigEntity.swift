import Foundation
import SwiftData

/// MCP server config entity (SwiftData)
@Model
final class MCPServerConfigEntity {
    @Attribute(.unique) var id: String
    var name: String
    var iconID: String?
    // Legacy stdio fields kept for schema stability.
    var command: String
    var argsData: Data
    var envData: Data?
    var transportKindRaw: String = MCPTransportKind.stdio.rawValue
    var transportData: Data = Data()
    var lifecycleRaw: String = MCPLifecyclePolicy.persistent.rawValue
    var disabledToolsData: Data?
    var isEnabled: Bool
    var runToolsAutomatically: Bool
    // Legacy mirror of lifecycle for old code paths.
    var isLongRunning: Bool

    init(
        id: String,
        name: String,
        iconID: String? = nil,
        command: String = "",
        argsData: Data = Data(),
        envData: Data? = nil,
        transportKindRaw: String,
        transportData: Data,
        lifecycleRaw: String = MCPLifecyclePolicy.persistent.rawValue,
        disabledToolsData: Data? = nil,
        isEnabled: Bool = false,
        runToolsAutomatically: Bool = true,
        isLongRunning: Bool = true
    ) {
        self.id = id
        self.name = name
        self.iconID = iconID
        self.command = command
        self.argsData = argsData
        self.envData = envData
        self.transportKindRaw = transportKindRaw
        self.transportData = transportData
        self.lifecycleRaw = lifecycleRaw
        self.disabledToolsData = disabledToolsData
        self.isEnabled = isEnabled
        self.runToolsAutomatically = runToolsAutomatically
        self.isLongRunning = isLongRunning
    }
}
