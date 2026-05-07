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

    func threadSupportsMCPTools(for thread: ConversationModelThreadEntity) -> Bool {
        let providerEntity = providers.first(where: { $0.id == thread.providerID })
        let providerTypeSnapshot = providerEntity.flatMap { ProviderType(rawValue: $0.typeRaw) } ?? ProviderType(rawValue: thread.providerID)
        let threadControls = (try? JSONDecoder().decode(GenerationControls.self, from: thread.modelConfigData)) ?? GenerationControls()
        let modelID = providerTypeSnapshot == .claudeManagedAgents
            ? ClaudeManagedAgentRuntime.resolvedRuntimeModelID(threadModelID: thread.modelID, controls: threadControls)
            : effectiveModelID(
                for: thread.modelID,
                providerEntity: providerEntity,
                providerType: providerTypeSnapshot
            )
        let modelInfoSnapshot = resolvedModelInfo(
            for: modelID,
            providerEntity: providerEntity,
            providerType: providerTypeSnapshot
        )
        let normalizedModelInfoSnapshot = modelInfoSnapshot.map {
            normalizedModelInfo($0, for: providerTypeSnapshot)
        }
        let resolvedModelSettingsSnapshot = normalizedModelInfoSnapshot.map {
            ModelSettingsResolver.resolve(model: $0, providerType: providerTypeSnapshot)
        }
        return threadSupportsMCPTools(
            providerType: providerTypeSnapshot,
            resolvedModelSettings: resolvedModelSettingsSnapshot
        )
    }
}
