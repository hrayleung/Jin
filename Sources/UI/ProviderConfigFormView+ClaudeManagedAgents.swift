import SwiftUI

extension ProviderConfigFormView {
    func scheduleClaudeManagedResourcesRefresh() {
        claudeManagedRefreshTask?.cancel()
        claudeManagedRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await refreshClaudeManagedResources()
        }
    }

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
            managedAgentManualEntry
            managedEnvironmentPicker
            managedEnvironmentManualEntry

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
                Text("If Anthropic does not return lists for your workspace, enter the Agent ID and Environment ID manually here. Those IDs will still seed new chat threads.")
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
                if let selectedAgentID = provider.claudeManagedDefaultAgentID,
                   !selectedAgentID.isEmpty,
                   !claudeManagedAgents.contains(where: { $0.id == selectedAgentID }) {
                    Text("Manual ID (\(selectedAgentID))").tag(selectedAgentID)
                }
                ForEach(claudeManagedAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if !claudeManagedAgents.isEmpty {
                Text(provider.claudeManagedDefaultAgentDisplayName ?? provider.claudeManagedDefaultAgentID ?? "No agent selected")
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
                .disabled(!canApplyClaudeManagedAgentIDDraft)

                Button("Clear") {
                    applyClaudeManagedAgentSelection(agentID: "")
                }
                .disabled(provider.claudeManagedDefaultAgentID == nil && trimmedClaudeManagedAgentIDDraft.isEmpty)
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
                if let selectedEnvironmentID = provider.claudeManagedDefaultEnvironmentID,
                   !selectedEnvironmentID.isEmpty,
                   !claudeManagedEnvironments.contains(where: { $0.id == selectedEnvironmentID }) {
                    Text("Manual ID (\(selectedEnvironmentID))").tag(selectedEnvironmentID)
                }
                ForEach(claudeManagedEnvironments) { environment in
                    Text(environment.name).tag(environment.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if !claudeManagedEnvironments.isEmpty {
                Text(provider.claudeManagedDefaultEnvironmentDisplayName ?? provider.claudeManagedDefaultEnvironmentID ?? "No environment selected")
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
                .disabled(!canApplyClaudeManagedEnvironmentIDDraft)

                Button("Clear") {
                    applyClaudeManagedEnvironmentSelection(environmentID: "")
                }
                .disabled(provider.claudeManagedDefaultEnvironmentID == nil && trimmedClaudeManagedEnvironmentIDDraft.isEmpty)
                .buttonStyle(.borderless)
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

            var fetchErrors: [String] = []

            do {
                let fetchedAgents = try await adapter.listAgents().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                claudeManagedAgents = fetchedAgents
            } catch {
                fetchErrors.append("Agents: \(error.localizedDescription)")
            }

            do {
                let fetchedEnvironments = try await adapter.listEnvironments().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                claudeManagedEnvironments = fetchedEnvironments
            } catch {
                fetchErrors.append("Environments: \(error.localizedDescription)")
            }

            claudeManagedResourceError = fetchErrors.isEmpty ? nil : fetchErrors.joined(separator: "\n")

            if let defaultAgentID = provider.claudeManagedDefaultAgentID {
                applyClaudeManagedAgentSelection(agentID: defaultAgentID, preserveSelectionIfMissing: true)
            }

            if let defaultEnvironmentID = provider.claudeManagedDefaultEnvironmentID {
                applyClaudeManagedEnvironmentSelection(environmentID: defaultEnvironmentID, preserveSelectionIfMissing: true)
            }
            syncClaudeManagedDefaultDrafts()
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
            syncClaudeManagedDefaultDrafts()
            return
        }

        guard let descriptor = claudeManagedAgents.first(where: { $0.id == trimmedID }) else {
            if !preserveSelectionIfMissing {
                provider.claudeManagedDefaultAgentID = trimmedID
                provider.claudeManagedDefaultAgentDisplayName = nil
                provider.claudeManagedDefaultAgentModelID = nil
                provider.claudeManagedDefaultAgentModelDisplayName = nil
                try? modelContext.save()
                syncClaudeManagedDefaultDrafts()
            }
            return
        }

        provider.claudeManagedDefaultAgentID = descriptor.id
        provider.claudeManagedDefaultAgentDisplayName = descriptor.name
        provider.claudeManagedDefaultAgentModelID = descriptor.modelID
        provider.claudeManagedDefaultAgentModelDisplayName = descriptor.modelDisplayName
        try? modelContext.save()
        syncClaudeManagedDefaultDrafts()
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
            syncClaudeManagedDefaultDrafts()
            return
        }

        guard let descriptor = claudeManagedEnvironments.first(where: { $0.id == trimmedID }) else {
            if !preserveSelectionIfMissing {
                provider.claudeManagedDefaultEnvironmentID = trimmedID
                provider.claudeManagedDefaultEnvironmentDisplayName = nil
                try? modelContext.save()
                syncClaudeManagedDefaultDrafts()
            }
            return
        }

        provider.claudeManagedDefaultEnvironmentID = descriptor.id
        provider.claudeManagedDefaultEnvironmentDisplayName = descriptor.name
        try? modelContext.save()
        syncClaudeManagedDefaultDrafts()
    }

    private var trimmedClaudeManagedAgentIDDraft: String {
        claudeManagedAgentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedClaudeManagedEnvironmentIDDraft: String {
        claudeManagedEnvironmentIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canApplyClaudeManagedAgentIDDraft: Bool {
        let currentID = provider.claudeManagedDefaultAgentID ?? ""
        return !trimmedClaudeManagedAgentIDDraft.isEmpty && trimmedClaudeManagedAgentIDDraft != currentID
    }

    private var canApplyClaudeManagedEnvironmentIDDraft: Bool {
        let currentID = provider.claudeManagedDefaultEnvironmentID ?? ""
        return !trimmedClaudeManagedEnvironmentIDDraft.isEmpty && trimmedClaudeManagedEnvironmentIDDraft != currentID
    }

    @MainActor
    func syncClaudeManagedDefaultDrafts() {
        claudeManagedAgentIDDraft = provider.claudeManagedDefaultAgentID ?? ""
        claudeManagedEnvironmentIDDraft = provider.claudeManagedDefaultEnvironmentID ?? ""
    }
}
