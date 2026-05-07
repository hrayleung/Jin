import SwiftUI

struct ClaudeManagedAgentProviderDefaultsSection: View {
    let summaryRows: [ClaudeManagedAgentSessionSettingsSheetSupport.SummaryRow]
    let useProviderDefaultsDisabled: Bool
    let onUseProviderDefaults: () -> Void

    var body: some View {
        JinSettingsCard(spacing: JinSpacing.small, padding: JinSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Label("Provider Defaults", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button("Use Default") {
                    onUseProviderDefaults()
                }
                .buttonStyle(.borderless)
                .disabled(useProviderDefaultsDisabled)
            }

            if summaryRows.isEmpty {
                Text("No default configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: JinSpacing.xSmall) {
                    ForEach(summaryRows) { row in
                        ClaudeManagedAgentConfigurationSummaryRow(title: row.title, value: row.value)
                    }
                }
                .padding(.top, JinSpacing.xSmall)
            }
        }
    }
}

struct ClaudeManagedAgentSessionConfigurationSection: View {
    @Binding var agentIDDraft: String
    @Binding var environmentIDDraft: String

    let availableAgents: [ClaudeManagedAgentDescriptor]
    let availableEnvironments: [ClaudeManagedEnvironmentDescriptor]
    let matchedAgentID: String
    let matchedEnvironmentID: String
    let draftError: String?
    let isRefreshingResources: Bool
    let onRefreshResources: () -> Void
    let onSelectAgent: (String) -> Void
    let onSelectEnvironment: (String) -> Void

    var body: some View {
        JinSettingsCard(spacing: JinSpacing.small, padding: JinSpacing.medium) {
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
    }

    private var agentConfigurationCard: some View {
        ClaudeManagedAgentResourceSelectionCard(
            title: "Agent",
            systemImage: "person.text.rectangle",
            pickerTitle: "Agent",
            textFieldPrompt: "agent_...",
            resources: availableAgents,
            selectedID: matchedAgentID,
            draftID: $agentIDDraft,
            onSelect: onSelectAgent,
            resourceName: { $0.name }
        )
    }

    private var environmentConfigurationCard: some View {
        ClaudeManagedAgentResourceSelectionCard(
            title: "Environment",
            systemImage: "macwindow",
            pickerTitle: "Environment",
            textFieldPrompt: "env_...",
            resources: availableEnvironments,
            selectedID: matchedEnvironmentID,
            draftID: $environmentIDDraft,
            onSelect: onSelectEnvironment,
            resourceName: { $0.name }
        )
    }
}

struct ClaudeManagedAgentCustomLabelsSection: View {
    @Binding var isExpanded: Bool
    @Binding var agentDisplayNameDraft: String
    @Binding var environmentDisplayNameDraft: String

    let hasCustomLabels: Bool

    var body: some View {
        JinSettingsCard(
            surface: isExpanded || hasCustomLabels ? .raised : .subtle,
            padding: JinSpacing.medium
        ) {
            DisclosureGroup(isExpanded: $isExpanded) {
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
        }
    }
}

private struct ClaudeManagedAgentConfigurationSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
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
}

private struct ClaudeManagedAgentResourceSelectionCard<Resource: Identifiable>: View where Resource.ID == String {
    let title: String
    let systemImage: String
    let pickerTitle: String
    let textFieldPrompt: String
    let resources: [Resource]
    let selectedID: String
    @Binding var draftID: String
    let onSelect: (String) -> Void
    let resourceName: (Resource) -> String

    var body: some View {
        ClaudeManagedAgentSelectionCard(title: title, systemImage: systemImage) {
            resourcePicker

            TextField(textFieldPrompt, text: $draftID)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var resourcePicker: some View {
        if !resources.isEmpty {
            Picker(
                pickerTitle,
                selection: Binding<String>(
                    get: { selectedID },
                    set: onSelect
                )
            ) {
                Text("Custom ID").tag("")
                ForEach(resources) { resource in
                    Text(resourceName(resource)).tag(resource.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

private struct ClaudeManagedAgentSelectionCard<Content: View>: View {
    private let title: String
    private let systemImage: String
    @ViewBuilder private let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(JinSpacing.small + 2)
        .jinSurface(.subtle, cornerRadius: JinRadius.medium)
    }
}
