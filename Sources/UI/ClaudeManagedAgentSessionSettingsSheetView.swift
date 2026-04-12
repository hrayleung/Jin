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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.medium) {
                    inheritanceSection
                    configurationSection
                    detailsSection
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
    }

    private var inheritanceSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Label("Provider Defaults", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("Use Default") {
                    onUseProviderDefaults()
                }
                .buttonStyle(.borderless)
                .disabled(providerDefaultAgentID.isEmpty && providerDefaultEnvironmentID.isEmpty)
            }

            if providerDefaultAgentID.isEmpty && providerDefaultEnvironmentID.isEmpty {
                Text("No default configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !providerDefaultAgentDisplayName.isEmpty || !providerDefaultAgentID.isEmpty {
                    Text("Agent: \(providerDefaultAgentDisplayName.isEmpty ? providerDefaultAgentID : providerDefaultAgentDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !providerDefaultEnvironmentDisplayName.isEmpty || !providerDefaultEnvironmentID.isEmpty {
                    Text("Environment: \(providerDefaultEnvironmentDisplayName.isEmpty ? providerDefaultEnvironmentID : providerDefaultEnvironmentDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Label("This Chat", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    onRefreshResources()
                } label: {
                    if isRefreshingResources {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
            }

            if !availableAgents.isEmpty {
                Picker(
                    "Agent",
                    selection: Binding<String>(
                        get: { matchedAgentID },
                        set: { newValue in
                            applyAgentSelection(newValue)
                        }
                    )
                ) {
                    Text("Custom ID").tag("")
                    ForEach(availableAgents) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Agent ID", text: $agentIDDraft, prompt: Text("agent_..."))
                .textFieldStyle(.roundedBorder)

            if !availableEnvironments.isEmpty {
                Picker(
                    "Environment",
                    selection: Binding<String>(
                        get: { matchedEnvironmentID },
                        set: { newValue in
                            applyEnvironmentSelection(newValue)
                        }
                    )
                ) {
                    Text("Custom ID").tag("")
                    ForEach(availableEnvironments) { environment in
                        Text(environment.name).tag(environment.id)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Environment ID", text: $environmentIDDraft, prompt: Text("env_..."))
                .textFieldStyle(.roundedBorder)

            if let draftError, !draftError.isEmpty {
                Text(draftError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label("Labels", systemImage: "tag")
                .font(.subheadline.weight(.semibold))

            TextField("Agent Name", text: $agentDisplayNameDraft, prompt: Text("Claude coding agent"))
                .textFieldStyle(.roundedBorder)
            TextField("Environment Name", text: $environmentDisplayNameDraft, prompt: Text("macOS workspace"))
                .textFieldStyle(.roundedBorder)

        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var matchedAgentID: String {
        availableAgents.contains(where: { $0.id == agentIDDraft }) ? agentIDDraft : ""
    }

    private var matchedEnvironmentID: String {
        availableEnvironments.contains(where: { $0.id == environmentIDDraft }) ? environmentIDDraft : ""
    }

    private func applyAgentSelection(_ id: String) {
        guard let selected = availableAgents.first(where: { $0.id == id }) else { return }
        agentIDDraft = selected.id
        agentDisplayNameDraft = selected.name
    }

    private func applyEnvironmentSelection(_ id: String) {
        guard let selected = availableEnvironments.first(where: { $0.id == id }) else { return }
        environmentIDDraft = selected.id
        environmentDisplayNameDraft = selected.name
    }
}
