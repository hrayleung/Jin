import Foundation

extension ChatAuxiliaryControlSupport {
    static func mcpToolsEnabledValue(controls: GenerationControls) -> Bool {
        controls.mcpTools?.enabled == true
    }

    static func usesCustomMCPServerSelection(controls: GenerationControls) -> Bool {
        controls.mcpTools?.enabledServerIDs != nil
    }

    static func setMCPToolsEnabled(
        _ isEnabled: Bool,
        controls: GenerationControls
    ) -> GenerationControls {
        var controls = controls
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: isEnabled)
        } else {
            controls.mcpTools?.enabled = isEnabled
        }
        return controls
    }

    static func eligibleMCPServers(
        from servers: [MCPServerConfigEntity]
    ) -> [MCPServerConfigEntity] {
        servers
            .filter { $0.isEnabled && $0.runToolsAutomatically }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func selectedMCPServerIDs(
        controls: GenerationControls,
        eligibleServers: [MCPServerConfigEntity]
    ) -> Set<String> {
        guard controls.mcpTools?.enabled == true else { return [] }
        let eligibleIDs = Set(eligibleServers.map(\.id))
        if let allowlist = controls.mcpTools?.enabledServerIDs {
            return Set(allowlist).intersection(eligibleIDs)
        }
        return eligibleIDs
    }

    static func toggleMCPServerSelection(
        controls: GenerationControls,
        eligibleServers: [MCPServerConfigEntity],
        serverID: String,
        isOn: Bool
    ) -> GenerationControls {
        var controls = controls
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        }

        let eligibleIDs = Set(eligibleServers.map(\.id))
        var selected = Set(controls.mcpTools?.enabledServerIDs ?? Array(eligibleIDs))
        if isOn {
            selected.insert(serverID)
        } else {
            selected.remove(serverID)
        }

        let normalized = selected.intersection(eligibleIDs)
        if normalized == eligibleIDs {
            controls.mcpTools?.enabledServerIDs = nil
        } else {
            controls.mcpTools?.enabledServerIDs = Array(normalized).sorted()
        }

        return controls
    }

    static func resetMCPServerSelection(controls: GenerationControls) -> GenerationControls {
        var controls = controls
        if controls.mcpTools == nil {
            controls.mcpTools = MCPToolsControls(enabled: true, enabledServerIDs: nil)
        } else {
            controls.mcpTools?.enabled = true
            controls.mcpTools?.enabledServerIDs = nil
        }
        return controls
    }

    static func resolvedMCPServerConfigs(
        controls: GenerationControls,
        supportsMCPToolsControl: Bool,
        servers: [MCPServerConfigEntity],
        perMessageOverrideServerIDs: Set<String> = []
    ) throws -> [MCPServerConfig] {
        guard supportsMCPToolsControl else { return [] }

        var effectiveControls = controls
        if !perMessageOverrideServerIDs.isEmpty {
            effectiveControls.mcpTools = MCPToolsControls(
                enabled: true,
                enabledServerIDs: Array(perMessageOverrideServerIDs).sorted()
            )
        }

        guard effectiveControls.mcpTools?.enabled == true else { return [] }

        let eligibleServers = eligibleMCPServers(from: servers)
        let eligibleIDs = Set(eligibleServers.map(\.id))
        let allowlist = effectiveControls.mcpTools?.enabledServerIDs
        let selectedIDs = allowlist.map(Set.init) ?? eligibleIDs
        let resolvedIDs = selectedIDs.intersection(eligibleIDs)

        return try eligibleServers
            .filter { resolvedIDs.contains($0.id) }
            .map { try $0.toConfig() }
    }
}
