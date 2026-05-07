import Foundation

extension ChatControlNormalizationSupport {
    static func normalizeMCPToolsControls(
        controls: inout GenerationControls,
        supportsMCPToolsControl: Bool
    ) {
        if supportsMCPToolsControl {
            if controls.mcpTools == nil {
                controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
            } else if controls.mcpTools?.enabledServerIDs?.isEmpty == true {
                controls.mcpTools?.enabledServerIDs = nil
            }
        } else {
            controls.mcpTools = nil
        }
    }
}
