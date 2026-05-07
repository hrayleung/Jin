import Foundation

enum ClaudeManagedAgentSessionSettingsSheetSupport {
    struct SummaryRow: Equatable, Identifiable {
        let title: String
        let value: String

        var id: String { title }
    }

    struct SelectionUpdate: Equatable {
        let idDraft: String
        let displayNameDraft: String?
    }

    static func useProviderDefaultsDisabled(
        providerDefaultAgentID: String,
        providerDefaultEnvironmentID: String
    ) -> Bool {
        !hasProviderDefaults(
            providerDefaultAgentID: providerDefaultAgentID,
            providerDefaultEnvironmentID: providerDefaultEnvironmentID
        )
    }

    static func providerDefaultSummaryRows(
        providerDefaultAgentID: String,
        providerDefaultEnvironmentID: String,
        providerDefaultAgentDisplayName: String,
        providerDefaultEnvironmentDisplayName: String
    ) -> [SummaryRow] {
        guard hasProviderDefaults(
            providerDefaultAgentID: providerDefaultAgentID,
            providerDefaultEnvironmentID: providerDefaultEnvironmentID
        ) else {
            return []
        }

        return [
            .init(
                title: "Agent",
                value: providerDefaultDisplayValue(
                    displayName: providerDefaultAgentDisplayName,
                    id: providerDefaultAgentID
                )
            ),
            .init(
                title: "Environment",
                value: providerDefaultDisplayValue(
                    displayName: providerDefaultEnvironmentDisplayName,
                    id: providerDefaultEnvironmentID
                )
            )
        ]
    }

    static func hasCustomLabels(
        agentDisplayNameDraft: String,
        environmentDisplayNameDraft: String
    ) -> Bool {
        agentDisplayNameDraft.trimmedNonEmpty != nil || environmentDisplayNameDraft.trimmedNonEmpty != nil
    }

    static func matchedAgentID(
        agentIDDraft: String,
        availableAgents: [ClaudeManagedAgentDescriptor]
    ) -> String {
        availableAgents.contains(where: { $0.id == agentIDDraft }) ? agentIDDraft : ""
    }

    static func matchedEnvironmentID(
        environmentIDDraft: String,
        availableEnvironments: [ClaudeManagedEnvironmentDescriptor]
    ) -> String {
        availableEnvironments.contains(where: { $0.id == environmentIDDraft }) ? environmentIDDraft : ""
    }

    static func agentSelectionUpdate(
        selectedID: String,
        availableAgents: [ClaudeManagedAgentDescriptor]
    ) -> SelectionUpdate? {
        let selectedID = selectedID.trimmed
        guard !selectedID.isEmpty else {
            return .init(idDraft: "", displayNameDraft: nil)
        }

        guard let selected = availableAgents.first(where: { $0.id == selectedID }) else {
            return nil
        }

        return .init(idDraft: selected.id, displayNameDraft: selected.name)
    }

    static func environmentSelectionUpdate(
        selectedID: String,
        availableEnvironments: [ClaudeManagedEnvironmentDescriptor]
    ) -> SelectionUpdate? {
        let selectedID = selectedID.trimmed
        guard !selectedID.isEmpty else {
            return .init(idDraft: "", displayNameDraft: nil)
        }

        guard let selected = availableEnvironments.first(where: { $0.id == selectedID }) else {
            return nil
        }

        return .init(idDraft: selected.id, displayNameDraft: selected.name)
    }

    private static func hasProviderDefaults(
        providerDefaultAgentID: String,
        providerDefaultEnvironmentID: String
    ) -> Bool {
        providerDefaultAgentID.trimmedNonEmpty != nil || providerDefaultEnvironmentID.trimmedNonEmpty != nil
    }

    private static func providerDefaultDisplayValue(displayName: String, id: String) -> String {
        displayName.trimmedNonEmpty ?? id.trimmed
    }
}
