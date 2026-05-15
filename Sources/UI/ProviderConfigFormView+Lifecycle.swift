import SwiftUI

extension ProviderConfigFormView {

    func providerFormLifecycle<Content: View>(_ content: Content) -> some View {
        content
            .task {
                await loadProviderFormData()
            }
            .onChange(of: apiKey) { _, _ in
                handleAPIKeyChanged()
            }
            .onChange(of: serviceAccountJSON) { _, _ in
                handleServiceAccountJSONChanged()
            }
            .onDisappear {
                cancelProviderFormTasks()
            }
    }

    func loadProviderFormData() async {
        await loadCredentials()
        await MainActor.run {
            hasLoadedCredentials = true
        }

        if providerType == .openrouter {
            await refreshOpenRouterUsage(force: true)
        }

        if providerType == .claudeManagedAgents {
            await MainActor.run {
                syncClaudeManagedDefaultDrafts()
            }
            await refreshClaudeManagedResources()
        }
    }

    func handleAPIKeyChanged() {
        guard hasLoadedCredentials else { return }
        scheduleCredentialSave()

        if providerType == .openrouter {
            scheduleOpenRouterUsageRefresh()
        }

        if providerType == .claudeManagedAgents {
            scheduleClaudeManagedResourcesRefresh()
        }
    }

    func handleServiceAccountJSONChanged() {
        guard hasLoadedCredentials else { return }
        scheduleCredentialSave()
    }

    func cancelProviderFormTasks() {
        credentialSaveTask?.cancel()
        openRouterUsageTask?.cancel()
        claudeManagedRefreshTask?.cancel()
    }
}
