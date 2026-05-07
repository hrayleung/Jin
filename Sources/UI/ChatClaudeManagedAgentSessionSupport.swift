import Foundation

enum ChatClaudeManagedAgentSessionSupport {
    struct ProviderDefaults: Equatable {
        let agentID: String
        let environmentID: String
        let agentDisplayName: String
        let environmentDisplayName: String

        init(
            agentID: String?,
            environmentID: String?,
            agentDisplayName: String?,
            environmentDisplayName: String?
        ) {
            self.agentID = agentID ?? ""
            self.environmentID = environmentID ?? ""
            self.agentDisplayName = agentDisplayName ?? ""
            self.environmentDisplayName = environmentDisplayName ?? ""
        }
    }

    struct SettingsDraft: Equatable {
        let agentID: String
        let environmentID: String
        let agentDisplayName: String
        let environmentDisplayName: String
    }

    struct Identity: Equatable {
        let agentID: String?
        let environmentID: String?

        init(controls: GenerationControls) {
            self.agentID = controls.claudeManagedAgentID
            self.environmentID = controls.claudeManagedEnvironmentID
        }
    }

    struct ControlUpdate {
        let controls: GenerationControls
        let resolvedControls: GenerationControls
        let didChangeIdentity: Bool
    }

    static func preparedSettingsDraft(
        controls: GenerationControls,
        providerDefaults: ProviderDefaults,
        resolvedAgentDisplayName: String,
        resolvedEnvironmentDisplayName: String?
    ) -> SettingsDraft {
        SettingsDraft(
            agentID: controls.claudeManagedAgentID ?? providerDefaults.agentID,
            environmentID: controls.claudeManagedEnvironmentID ?? providerDefaults.environmentID,
            agentDisplayName: resolvedAgentDisplayName,
            environmentDisplayName: resolvedEnvironmentDisplayName ?? providerDefaults.environmentDisplayName
        )
    }

    static func settingsDraftUsingProviderDefaults(
        _ providerDefaults: ProviderDefaults
    ) -> SettingsDraft {
        SettingsDraft(
            agentID: providerDefaults.agentID,
            environmentID: providerDefaults.environmentID,
            agentDisplayName: providerDefaults.agentDisplayName,
            environmentDisplayName: providerDefaults.environmentDisplayName
        )
    }

    static func settingsDraftFillingResourceNames(
        _ draft: SettingsDraft,
        availableAgents: [ClaudeManagedAgentDescriptor],
        availableEnvironments: [ClaudeManagedEnvironmentDescriptor]
    ) -> SettingsDraft {
        var agentDisplayName = draft.agentDisplayName
        var environmentDisplayName = draft.environmentDisplayName

        if agentDisplayName.isEmpty,
           let selected = availableAgents.first(where: { $0.id == draft.agentID }) {
            agentDisplayName = selected.name
        }
        if environmentDisplayName.isEmpty,
           let selected = availableEnvironments.first(where: { $0.id == draft.environmentID }) {
            environmentDisplayName = selected.name
        }

        return SettingsDraft(
            agentID: draft.agentID,
            environmentID: draft.environmentID,
            agentDisplayName: agentDisplayName,
            environmentDisplayName: environmentDisplayName
        )
    }

    static func sortedAgents(
        _ agents: [ClaudeManagedAgentDescriptor]
    ) -> [ClaudeManagedAgentDescriptor] {
        agents.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func sortedEnvironments(
        _ environments: [ClaudeManagedEnvironmentDescriptor]
    ) -> [ClaudeManagedEnvironmentDescriptor] {
        environments.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func controlsApplyingAgentSelection(
        _ descriptor: ClaudeManagedAgentDescriptor,
        currentControls: GenerationControls,
        resolveControls: (GenerationControls) -> GenerationControls
    ) -> ControlUpdate {
        var updatedControls = currentControls
        updatedControls.claudeManagedAgentID = descriptor.id
        updatedControls.claudeManagedAgentDisplayName = descriptor.name
        updatedControls.claudeManagedAgentModelID = descriptor.modelID
        updatedControls.claudeManagedAgentModelDisplayName = descriptor.modelDisplayName

        return controlUpdate(
            currentControls: currentControls,
            updatedControls: updatedControls,
            resolveControls: resolveControls
        )
    }

    static func controlUpdate(
        currentControls: GenerationControls,
        updatedControls: GenerationControls,
        resolveControls: (GenerationControls) -> GenerationControls
    ) -> ControlUpdate {
        let currentIdentity = Identity(controls: resolveControls(currentControls))
        let resolvedUpdatedControls = resolveControls(updatedControls)
        let updatedIdentity = Identity(controls: resolvedUpdatedControls)
        var finalControls = updatedControls
        let didChangeIdentity = updatedIdentity != currentIdentity

        if didChangeIdentity {
            finalControls.clearClaudeManagedAgentSessionState()
        }

        return ControlUpdate(
            controls: finalControls,
            resolvedControls: resolvedUpdatedControls,
            didChangeIdentity: didChangeIdentity
        )
    }
}
