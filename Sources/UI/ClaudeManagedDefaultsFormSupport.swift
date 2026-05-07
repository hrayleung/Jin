import Foundation

enum ClaudeManagedDefaultsFormSupport {
    struct AgentDefaults: Equatable {
        let id: String?
        let displayName: String?
        let modelID: String?
        let modelDisplayName: String?
    }

    struct EnvironmentDefaults: Equatable {
        let id: String?
        let displayName: String?
    }

    struct SummaryLine: Equatable, Identifiable {
        enum Kind: String {
            case agentID
            case environmentID
            case remoteModel
        }

        let kind: Kind
        let text: String

        var id: Kind { kind }
    }

    static let manualHintText = "If Anthropic does not return lists for your workspace, enter the Agent ID and Environment ID manually here. Those IDs will still seed new chat threads."

    static func trimmedID(_ id: String) -> String {
        id.trimmedNonEmpty ?? ""
    }

    static func isRefreshDisabled(apiKey: String, isRefreshing: Bool) -> Bool {
        trimmedID(apiKey).isEmpty || isRefreshing
    }

    static func agentDefaultsUpdate(
        agentID: String,
        availableAgents: [ClaudeManagedAgentDescriptor],
        preserveSelectionIfMissing: Bool
    ) -> AgentDefaults? {
        let selectedID = trimmedID(agentID)
        guard !selectedID.isEmpty else {
            return .init(id: nil, displayName: nil, modelID: nil, modelDisplayName: nil)
        }

        guard let descriptor = availableAgents.first(where: { $0.id == selectedID }) else {
            guard !preserveSelectionIfMissing else { return nil }
            return .init(id: selectedID, displayName: nil, modelID: nil, modelDisplayName: nil)
        }

        return .init(
            id: descriptor.id,
            displayName: descriptor.name,
            modelID: descriptor.modelID,
            modelDisplayName: descriptor.modelDisplayName
        )
    }

    static func environmentDefaultsUpdate(
        environmentID: String,
        availableEnvironments: [ClaudeManagedEnvironmentDescriptor],
        preserveSelectionIfMissing: Bool
    ) -> EnvironmentDefaults? {
        let selectedID = trimmedID(environmentID)
        guard !selectedID.isEmpty else {
            return .init(id: nil, displayName: nil)
        }

        guard let descriptor = availableEnvironments.first(where: { $0.id == selectedID }) else {
            guard !preserveSelectionIfMissing else { return nil }
            return .init(id: selectedID, displayName: nil)
        }

        return .init(id: descriptor.id, displayName: descriptor.name)
    }

    static func manualPickerFallbackID(
        selectedID: String?,
        availableIDs: [String]
    ) -> String? {
        guard let selectedID = normalizedID(selectedID),
              !availableIDs.contains(selectedID) else {
            return nil
        }

        return selectedID
    }

    static func manualPickerFallbackLabel(for id: String) -> String {
        "Manual ID (\(id))"
    }

    static func selectedAgentDetailText(
        hasAvailableAgents: Bool,
        displayName: String?,
        selectedID: String?
    ) -> String? {
        selectedDetailText(
            hasAvailableItems: hasAvailableAgents,
            displayName: displayName,
            selectedID: selectedID,
            emptySelectionText: "No agent selected"
        )
    }

    static func selectedEnvironmentDetailText(
        hasAvailableEnvironments: Bool,
        displayName: String?,
        selectedID: String?
    ) -> String? {
        selectedDetailText(
            hasAvailableItems: hasAvailableEnvironments,
            displayName: displayName,
            selectedID: selectedID,
            emptySelectionText: "No environment selected"
        )
    }

    static func canApplyDraft(
        _ draft: String,
        currentID: String?
    ) -> Bool {
        let trimmedDraft = trimmedID(draft)
        return !trimmedDraft.isEmpty && trimmedDraft != (currentID ?? "")
    }

    static func canClearDraft(
        _ draft: String,
        currentID: String?
    ) -> Bool {
        currentID != nil || !trimmedID(draft).isEmpty
    }

    static func selectedSummaryLines(
        agentID: String?,
        environmentID: String?,
        agentModelID: String?,
        agentModelDisplayName: String?
    ) -> [SummaryLine] {
        let normalizedAgentID = normalizedID(agentID)
        let normalizedEnvironmentID = normalizedID(environmentID)
        guard normalizedAgentID != nil || normalizedEnvironmentID != nil else {
            return []
        }

        var lines: [SummaryLine] = []
        if let normalizedAgentID {
            lines.append(.init(kind: .agentID, text: "Agent ID: \(normalizedAgentID)"))
        }
        if let normalizedEnvironmentID {
            lines.append(.init(kind: .environmentID, text: "Environment ID: \(normalizedEnvironmentID)"))
        }
        if let normalizedModelID = normalizedID(agentModelID) {
            let modelLabel = normalizedID(agentModelDisplayName) ?? normalizedModelID
            lines.append(.init(kind: .remoteModel, text: "Remote model: \(modelLabel)"))
        }

        return lines
    }

    static func shouldShowManualHint(
        hasAvailableAgents: Bool,
        hasAvailableEnvironments: Bool
    ) -> Bool {
        !hasAvailableAgents || !hasAvailableEnvironments
    }

    private static func selectedDetailText(
        hasAvailableItems: Bool,
        displayName: String?,
        selectedID: String?,
        emptySelectionText: String
    ) -> String? {
        guard hasAvailableItems else { return nil }
        return normalizedID(displayName) ?? normalizedID(selectedID) ?? emptySelectionText
    }

    private static func normalizedID(_ id: String?) -> String? {
        id?.trimmedNonEmpty
    }
}
