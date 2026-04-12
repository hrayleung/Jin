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
        .onAppear {
            if hasCustomLabels {
                areCustomLabelsExpanded = true
            }
        }
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
                VStack(spacing: JinSpacing.xSmall) {
                    configurationSummaryRow(
                        title: "Agent",
                        value: providerDefaultAgentDisplayName.isEmpty ? providerDefaultAgentID : providerDefaultAgentDisplayName
                    )
                    configurationSummaryRow(
                        title: "Environment",
                        value: providerDefaultEnvironmentDisplayName.isEmpty ? providerDefaultEnvironmentID : providerDefaultEnvironmentDisplayName
                    )
                }
                .padding(.top, JinSpacing.xSmall)
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

            HStack(alignment: .top, spacing: JinSpacing.medium) {
                agentConfigurationCard
                environmentConfigurationCard
            }

            if let draftError, !draftError.isEmpty {
                Text(draftError)
                    .jinInlineErrorText()
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $areCustomLabelsExpanded) {
            VStack(alignment: .leading, spacing: JinSpacing.small) {
                TextField("Agent Name", text: $agentDisplayNameDraft, prompt: Text("Claude coding agent"))
                    .textFieldStyle(.roundedBorder)
                TextField("Environment Name", text: $environmentDisplayNameDraft, prompt: Text("macOS workspace"))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.top, JinSpacing.small)
        } label: {
            HStack(spacing: JinSpacing.small) {
                Label("Custom Labels", systemImage: "tag")
                    .font(.subheadline.weight(.semibold))

                if hasCustomLabels {
                    Text("Set")
                        .jinTagStyle()
                }
            }
        }
        .padding(JinSpacing.medium)
        .jinSurface(areCustomLabelsExpanded || hasCustomLabels ? .raised : .subtle, cornerRadius: JinRadius.large)
    }

    private var agentConfigurationCard: some View {
        selectionCard(title: "Agent", systemImage: "person.text.rectangle") {
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
                .labelsHidden()
                .pickerStyle(.menu)
            }

            TextField("agent_...", text: $agentIDDraft)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var environmentConfigurationCard: some View {
        selectionCard(title: "Environment", systemImage: "macwindow") {
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
                .labelsHidden()
                .pickerStyle(.menu)
            }

            TextField("env_...", text: $environmentIDDraft)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var hasCustomLabels: Bool {
        !agentDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !environmentDisplayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchedAgentID: String {
        availableAgents.contains(where: { $0.id == agentIDDraft }) ? agentIDDraft : ""
    }

    private var matchedEnvironmentID: String {
        availableEnvironments.contains(where: { $0.id == environmentIDDraft }) ? environmentIDDraft : ""
    }

    private func configurationSummaryRow(title: String, value: String) -> some View {
        HStack(spacing: JinSpacing.small) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.vertical, JinSpacing.small - 1)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }

    private func selectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(JinSpacing.small + 2)
        .jinSurface(.subtle, cornerRadius: JinRadius.medium)
    }

    private func applyAgentSelection(_ id: String) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            agentIDDraft = ""
            return
        }

        guard let selected = availableAgents.first(where: { $0.id == trimmedID }) else { return }
        agentIDDraft = selected.id
        agentDisplayNameDraft = selected.name
    }

    private func applyEnvironmentSelection(_ id: String) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            environmentIDDraft = ""
            return
        }

        guard let selected = availableEnvironments.first(where: { $0.id == trimmedID }) else { return }
        environmentIDDraft = selected.id
        environmentDisplayNameDraft = selected.name
    }
}
