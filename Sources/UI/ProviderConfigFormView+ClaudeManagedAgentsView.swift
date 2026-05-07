import SwiftUI

extension ProviderConfigFormView {

    var claudeManagedDefaultsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            claudeManagedDefaultsHeader

            if let claudeManagedResourceError, !claudeManagedResourceError.isEmpty {
                JinSettingsErrorText(text: claudeManagedResourceError)
            }

            managedAgentPicker
            managedAgentManualEntry
            managedEnvironmentPicker
            managedEnvironmentManualEntry
            selectedManagedDefaultsSummary
            manualManagedDefaultsHint
        }
    }

    private var claudeManagedDefaultsHeader: some View {
        HStack(alignment: .center, spacing: JinSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default Agent & Environment")
                    .font(.subheadline.weight(.semibold))
                Text("These values seed new chat threads for this provider. Threads can override them later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await refreshClaudeManagedResources(force: true) }
            } label: {
                if isRefreshingClaudeManagedResources {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(claudeManagedDefaultsRefreshDisabled)
        }
    }

    private var managedAgentPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default Agent")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "",
                selection: Binding<String>(
                    get: { provider.claudeManagedDefaultAgentID ?? "" },
                    set: { newValue in
                        applyClaudeManagedAgentSelection(agentID: newValue)
                    }
                )
            ) {
                Text("None").tag("")
                if let fallbackID = manualAgentPickerFallbackID {
                    Text(ClaudeManagedDefaultsFormSupport.manualPickerFallbackLabel(for: fallbackID))
                        .tag(fallbackID)
                }
                ForEach(claudeManagedAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if let selectedAgentDetailText {
                Text(selectedAgentDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var managedAgentManualEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent ID")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("agent_...", text: $claudeManagedAgentIDDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: JinSpacing.small) {
                Button("Use ID") {
                    applyClaudeManagedAgentSelection(agentID: claudeManagedAgentIDDraft)
                }
                .disabled(!canApplyManagedAgentDraft)

                Button("Clear") {
                    applyClaudeManagedAgentSelection(agentID: "")
                }
                .disabled(!canClearManagedAgentDraft)
                .buttonStyle(.borderless)
            }
        }
    }

    private var managedEnvironmentPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default Environment")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "",
                selection: Binding<String>(
                    get: { provider.claudeManagedDefaultEnvironmentID ?? "" },
                    set: { newValue in
                        applyClaudeManagedEnvironmentSelection(environmentID: newValue)
                    }
                )
            ) {
                Text("None").tag("")
                if let fallbackID = manualEnvironmentPickerFallbackID {
                    Text(ClaudeManagedDefaultsFormSupport.manualPickerFallbackLabel(for: fallbackID))
                        .tag(fallbackID)
                }
                ForEach(claudeManagedEnvironments) { environment in
                    Text(environment.name).tag(environment.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if let selectedEnvironmentDetailText {
                Text(selectedEnvironmentDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var managedEnvironmentManualEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Environment ID")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("env_...", text: $claudeManagedEnvironmentIDDraft)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: JinSpacing.small) {
                Button("Use ID") {
                    applyClaudeManagedEnvironmentSelection(environmentID: claudeManagedEnvironmentIDDraft)
                }
                .disabled(!canApplyManagedEnvironmentDraft)

                Button("Clear") {
                    applyClaudeManagedEnvironmentSelection(environmentID: "")
                }
                .disabled(!canClearManagedEnvironmentDraft)
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var selectedManagedDefaultsSummary: some View {
        let lines = selectedManagedDefaultsSummaryLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var manualManagedDefaultsHint: some View {
        if shouldShowManualManagedDefaultsHint {
            Text(ClaudeManagedDefaultsFormSupport.manualHintText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var claudeManagedDefaultsRefreshDisabled: Bool {
        ClaudeManagedDefaultsFormSupport.isRefreshDisabled(
            apiKey: apiKey,
            isRefreshing: isRefreshingClaudeManagedResources
        )
    }

    private var manualAgentPickerFallbackID: String? {
        ClaudeManagedDefaultsFormSupport.manualPickerFallbackID(
            selectedID: provider.claudeManagedDefaultAgentID,
            availableIDs: claudeManagedAgents.map(\.id)
        )
    }

    private var selectedAgentDetailText: String? {
        ClaudeManagedDefaultsFormSupport.selectedAgentDetailText(
            hasAvailableAgents: !claudeManagedAgents.isEmpty,
            displayName: provider.claudeManagedDefaultAgentDisplayName,
            selectedID: provider.claudeManagedDefaultAgentID
        )
    }

    private var canApplyManagedAgentDraft: Bool {
        ClaudeManagedDefaultsFormSupport.canApplyDraft(
            claudeManagedAgentIDDraft,
            currentID: provider.claudeManagedDefaultAgentID
        )
    }

    private var canClearManagedAgentDraft: Bool {
        ClaudeManagedDefaultsFormSupport.canClearDraft(
            claudeManagedAgentIDDraft,
            currentID: provider.claudeManagedDefaultAgentID
        )
    }

    private var manualEnvironmentPickerFallbackID: String? {
        ClaudeManagedDefaultsFormSupport.manualPickerFallbackID(
            selectedID: provider.claudeManagedDefaultEnvironmentID,
            availableIDs: claudeManagedEnvironments.map(\.id)
        )
    }

    private var selectedEnvironmentDetailText: String? {
        ClaudeManagedDefaultsFormSupport.selectedEnvironmentDetailText(
            hasAvailableEnvironments: !claudeManagedEnvironments.isEmpty,
            displayName: provider.claudeManagedDefaultEnvironmentDisplayName,
            selectedID: provider.claudeManagedDefaultEnvironmentID
        )
    }

    private var canApplyManagedEnvironmentDraft: Bool {
        ClaudeManagedDefaultsFormSupport.canApplyDraft(
            claudeManagedEnvironmentIDDraft,
            currentID: provider.claudeManagedDefaultEnvironmentID
        )
    }

    private var canClearManagedEnvironmentDraft: Bool {
        ClaudeManagedDefaultsFormSupport.canClearDraft(
            claudeManagedEnvironmentIDDraft,
            currentID: provider.claudeManagedDefaultEnvironmentID
        )
    }

    private var selectedManagedDefaultsSummaryLines: [ClaudeManagedDefaultsFormSupport.SummaryLine] {
        ClaudeManagedDefaultsFormSupport.selectedSummaryLines(
            agentID: provider.claudeManagedDefaultAgentID,
            environmentID: provider.claudeManagedDefaultEnvironmentID,
            agentModelID: provider.claudeManagedDefaultAgentModelID,
            agentModelDisplayName: provider.claudeManagedDefaultAgentModelDisplayName
        )
    }

    private var shouldShowManualManagedDefaultsHint: Bool {
        ClaudeManagedDefaultsFormSupport.shouldShowManualHint(
            hasAvailableAgents: !claudeManagedAgents.isEmpty,
            hasAvailableEnvironments: !claudeManagedEnvironments.isEmpty
        )
    }
}
