import Foundation

enum ChatMCPToolCapabilitySupport {
    static func supportsMCPTools(
        providerType: ProviderType?,
        resolvedModelSettings: ResolvedModelSettings?
    ) -> Bool {
        guard !ManagedAgentUIVisibilitySupport.hidesInternalUI(providerType: providerType) else {
            return false
        }
        guard resolvedModelSettings?.capabilities.contains(.imageGeneration) != true,
              resolvedModelSettings?.capabilities.contains(.videoGeneration) != true else {
            return false
        }
        return resolvedModelSettings?.capabilities.contains(.toolCalling) == true
    }
}
