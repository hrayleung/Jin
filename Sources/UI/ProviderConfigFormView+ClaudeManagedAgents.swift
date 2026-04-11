import SwiftUI

extension ProviderConfigFormView {
    var claudeManagedDefaultsSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
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
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRefreshingClaudeManagedResources)
            }

            if let claudeManagedResourceError, !claudeManagedResourceError.isEmpty {
                Text(claudeManagedResourceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            managedAgentPicker
            managedEnvironmentPicker

            if provider.claudeManagedDefaultAgentID != nil || provider.claudeManagedDefaultEnvironmentID != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let agentID = provider.claudeManagedDefaultAgentID {
                        Text("Agent ID: \(agentID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let environmentID = provider.claudeManagedDefaultEnvironmentID {
                        Text("Environment ID: \(environmentID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let modelID = provider.claudeManagedDefaultAgentModelID {
                        Text("Remote model: \(provider.claudeManagedDefaultAgentModelDisplayName ?? modelID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if claudeManagedAgents.isEmpty || claudeManagedEnvironments.isEmpty {
                Text("If the API does not return lists for your workspace, you can still paste IDs manually in a thread’s session settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                ForEach(claudeManagedAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if !claudeManagedAgents.isEmpty {
                Text(provider.claudeManagedDefaultAgentDisplayName ?? "No agent selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                ForEach(claudeManagedEnvironments) { environment in
                    Text(environment.name).tag(environment.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if !claudeManagedEnvironments.isEmpty {
                Text(provider.claudeManagedDefaultEnvironmentDisplayName ?? "No environment selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    func refreshClaudeManagedResources(force: Bool = false) async {
        guard providerType == .claudeManagedAgents else { return }
        guard !isRefreshingClaudeManagedResources else { return }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            if force {
                claudeManagedResourceError = "Enter an Anthropic API key to load Managed Agents resources."
            }
            return
        }

        isRefreshingClaudeManagedResources = true
        claudeManagedResourceError = nil
        defer { isRefreshingClaudeManagedResources = false }

        do {
            try await saveCredentials()
            guard let config = try? provider.toDomain(),
                  let adapter = try await providerManager.createAdapter(for: config) as? ClaudeManagedAgentsAdapter else {
                throw LLMError.invalidRequest(message: "Failed to initialize Claude Managed Agents adapter.")
            }

            async let agents = adapter.listAgents()
            async let environments = adapter.listEnvironments()

            let fetchedAgents = try await agents.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let fetchedEnvironments = try await environments.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            claudeManagedAgents = fetchedAgents
            claudeManagedEnvironments = fetchedEnvironments
            claudeManagedResourceError = nil

            if let defaultAgentID = provider.claudeManagedDefaultAgentID,
               !fetchedAgents.contains(where: { $0.id == defaultAgentID }) {
                applyClaudeManagedAgentSelection(agentID: "")
            } else if let defaultAgentID = provider.claudeManagedDefaultAgentID {
                applyClaudeManagedAgentSelection(agentID: defaultAgentID, preserveSelectionIfMissing: true)
            }

            if let defaultEnvironmentID = provider.claudeManagedDefaultEnvironmentID,
               !fetchedEnvironments.contains(where: { $0.id == defaultEnvironmentID }) {
                applyClaudeManagedEnvironmentSelection(environmentID: "")
            } else if let defaultEnvironmentID = provider.claudeManagedDefaultEnvironmentID {
                applyClaudeManagedEnvironmentSelection(environmentID: defaultEnvironmentID, preserveSelectionIfMissing: true)
            }
        } catch {
            claudeManagedResourceError = error.localizedDescription
        }
    }

    @MainActor
    func applyClaudeManagedAgentSelection(
        agentID: String,
        preserveSelectionIfMissing: Bool = false
    ) {
        let trimmedID = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            provider.claudeManagedDefaultAgentID = nil
            provider.claudeManagedDefaultAgentDisplayName = nil
            provider.claudeManagedDefaultAgentModelID = nil
            provider.claudeManagedDefaultAgentModelDisplayName = nil
            try? modelContext.save()
            return
        }

        guard let descriptor = claudeManagedAgents.first(where: { $0.id == trimmedID }) else {
            if !preserveSelectionIfMissing {
                provider.claudeManagedDefaultAgentID = trimmedID
                try? modelContext.save()
            }
            return
        }

        provider.claudeManagedDefaultAgentID = descriptor.id
        provider.claudeManagedDefaultAgentDisplayName = descriptor.name
        provider.claudeManagedDefaultAgentModelID = descriptor.modelID
        provider.claudeManagedDefaultAgentModelDisplayName = descriptor.modelDisplayName
        try? modelContext.save()
    }

    @MainActor
    func applyClaudeManagedEnvironmentSelection(
        environmentID: String,
        preserveSelectionIfMissing: Bool = false
    ) {
        let trimmedID = environmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            provider.claudeManagedDefaultEnvironmentID = nil
            provider.claudeManagedDefaultEnvironmentDisplayName = nil
            try? modelContext.save()
            return
        }

        guard let descriptor = claudeManagedEnvironments.first(where: { $0.id == trimmedID }) else {
            if !preserveSelectionIfMissing {
                provider.claudeManagedDefaultEnvironmentID = trimmedID
                try? modelContext.save()
            }
            return
        }

        provider.claudeManagedDefaultEnvironmentID = descriptor.id
        provider.claudeManagedDefaultEnvironmentDisplayName = descriptor.name
        try? modelContext.save()
    }
}
