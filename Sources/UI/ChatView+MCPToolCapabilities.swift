import Foundation

// MARK: - MCP Tool Capability

extension ChatView {

    func threadSupportsMCPTools(
        providerType: ProviderType?,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        ChatMCPToolCapabilitySupport.supportsMCPTools(
            providerType: providerType,
            resolvedModelSettings: resolvedModelSettings
        )
    }
}
