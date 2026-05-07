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
                let fetchedAgents = ChatClaudeManagedAgentSessionSupport.sortedAgents(try await adapter.listAgents())
                claudeManagedAgents = fetchedAgents
            } catch {
                fetchErrors.append("Agents: \(error.localizedDescription)")
            }

            do {
                let fetchedEnvironments = ChatClaudeManagedAgentSessionSupport.sortedEnvironments(try await adapter.listEnvironments())
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
        guard let update = ClaudeManagedDefaultsFormSupport.agentDefaultsUpdate(
            agentID: agentID,
            availableAgents: claudeManagedAgents,
            preserveSelectionIfMissing: preserveSelectionIfMissing
        ) else { return }

        provider.claudeManagedDefaultAgentID = update.id
        provider.claudeManagedDefaultAgentDisplayName = update.displayName
        provider.claudeManagedDefaultAgentModelID = update.modelID
        provider.claudeManagedDefaultAgentModelDisplayName = update.modelDisplayName
        try? modelContext.save()
        syncClaudeManagedDefaultDrafts()
    }

    @MainActor
    func applyClaudeManagedEnvironmentSelection(
        environmentID: String,
        preserveSelectionIfMissing: Bool = false
    ) {
        guard let update = ClaudeManagedDefaultsFormSupport.environmentDefaultsUpdate(
            environmentID: environmentID,
            availableEnvironments: claudeManagedEnvironments,
            preserveSelectionIfMissing: preserveSelectionIfMissing
        ) else { return }

        provider.claudeManagedDefaultEnvironmentID = update.id
        provider.claudeManagedDefaultEnvironmentDisplayName = update.displayName
        try? modelContext.save()
        syncClaudeManagedDefaultDrafts()
    }

    @MainActor
    func syncClaudeManagedDefaultDrafts() {
        claudeManagedAgentIDDraft = provider.claudeManagedDefaultAgentID ?? ""
        claudeManagedEnvironmentIDDraft = provider.claudeManagedDefaultEnvironmentID ?? ""
    }
}
