import SwiftUI

struct ClaudeManagedAgentSessionSettingsSheetView: View {
    @Binding var agentIDDraft: String
    @Binding var environmentIDDraft: String
    @Binding var agentDisplayNameDraft: String
    @Binding var environmentDisplayNameDraft: String
    @Binding var draftError: String?

    let availableAgents: [ClaudeManagedAgentDescriptor]
    let availableEnvironments: [ClaudeManagedEnvironmentDescriptor]
    let isRefreshingResources: Bool
    let providerDefaultAgentID: String
    let providerDefaultEnvironmentID: String
    let providerDefaultAgentDisplayName: String
    let providerDefaultEnvironmentDisplayName: String

    var onRefreshResources: () -> Void
    var onUseProviderDefaults: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    @State private var areCustomLabelsExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    ClaudeManagedAgentProviderDefaultsSection(
                        summaryRows: providerDefaultSummaryRows,
                        useProviderDefaultsDisabled: useProviderDefaultsDisabled,
                        onUseProviderDefaults: onUseProviderDefaults
                    )

                    ClaudeManagedAgentSessionConfigurationSection(
                        agentIDDraft: $agentIDDraft,
                        environmentIDDraft: $environmentIDDraft,
                        availableAgents: availableAgents,
                        availableEnvironments: availableEnvironments,
                        matchedAgentID: matchedAgentID,
                        matchedEnvironmentID: matchedEnvironmentID,
                        draftError: draftError,
                        isRefreshingResources: isRefreshingResources,
                        onRefreshResources: onRefreshResources,
                        onSelectAgent: applyAgentSelection,
                        onSelectEnvironment: applyEnvironmentSelection
                    )

                    ClaudeManagedAgentCustomLabelsSection(
                        isExpanded: $areCustomLabelsExpanded,
                        agentDisplayNameDraft: $agentDisplayNameDraft,
                        environmentDisplayNameDraft: $environmentDisplayNameDraft,
                        hasCustomLabels: hasCustomLabels
                    )
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle("Claude Managed Agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 420, idealHeight: 500)
        .onAppear {
            if hasCustomLabels {
                areCustomLabelsExpanded = true
            }
        }
    }

    private var hasCustomLabels: Bool {
        ClaudeManagedAgentSessionSettingsSheetSupport.hasCustomLabels(
            agentDisplayNameDraft: agentDisplayNameDraft,
            environmentDisplayNameDraft: environmentDisplayNameDraft
        )
    }

    private var matchedAgentID: String {
        ClaudeManagedAgentSessionSettingsSheetSupport.matchedAgentID(
            agentIDDraft: agentIDDraft,
            availableAgents: availableAgents
        )
    }

    private var matchedEnvironmentID: String {
        ClaudeManagedAgentSessionSettingsSheetSupport.matchedEnvironmentID(
            environmentIDDraft: environmentIDDraft,
            availableEnvironments: availableEnvironments
        )
    }

    private var useProviderDefaultsDisabled: Bool {
        ClaudeManagedAgentSessionSettingsSheetSupport.useProviderDefaultsDisabled(
            providerDefaultAgentID: providerDefaultAgentID,
            providerDefaultEnvironmentID: providerDefaultEnvironmentID
        )
    }

    private var providerDefaultSummaryRows: [ClaudeManagedAgentSessionSettingsSheetSupport.SummaryRow] {
        ClaudeManagedAgentSessionSettingsSheetSupport.providerDefaultSummaryRows(
            providerDefaultAgentID: providerDefaultAgentID,
            providerDefaultEnvironmentID: providerDefaultEnvironmentID,
            providerDefaultAgentDisplayName: providerDefaultAgentDisplayName,
            providerDefaultEnvironmentDisplayName: providerDefaultEnvironmentDisplayName
        )
    }

    private func applyAgentSelection(_ id: String) {
        guard let update = ClaudeManagedAgentSessionSettingsSheetSupport.agentSelectionUpdate(
            selectedID: id,
            availableAgents: availableAgents
        ) else { return }

        agentIDDraft = update.idDraft
        if let displayNameDraft = update.displayNameDraft {
            agentDisplayNameDraft = displayNameDraft
        }
    }

    private func applyEnvironmentSelection(_ id: String) {
        guard let update = ClaudeManagedAgentSessionSettingsSheetSupport.environmentSelectionUpdate(
            selectedID: id,
            availableEnvironments: availableEnvironments
        ) else { return }

        environmentIDDraft = update.idDraft
        if let displayNameDraft = update.displayNameDraft {
            environmentDisplayNameDraft = displayNameDraft
        }
    }
}
