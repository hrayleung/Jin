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
            .onChange(of: codexAuthMode) { _, _ in
                handleCodexAuthModeChanged()
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
            if providerType == .codexAppServer {
                loadCodexWorkingDirectoryPresets()
                codexServerController.refreshManagedProcesses()
            } else {
                codexWorkingDirectoryPresets = []
            }
            hasLoadedCredentials = true
        }

        if providerType == .openrouter {
            await refreshOpenRouterUsage(force: true)
        }

        if providerType == .codexAppServer, codexAuthMode == .chatGPT {
            await refreshCodexAccountStatus(forceRefreshToken: false)
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

    func handleCodexAuthModeChanged() {
        guard hasLoadedCredentials else { return }
        codexAuthTask?.cancel()
        codexPendingLoginID = nil
        codexAccount = nil
        codexRateLimit = nil
        codexAuthStatus = .idle
        scheduleCredentialSave()

        if codexAuthMode == .chatGPT {
            Task { await refreshCodexAccountStatus(forceRefreshToken: false) }
        }
    }

    func handleServiceAccountJSONChanged() {
        guard hasLoadedCredentials else { return }
        scheduleCredentialSave()
    }

    func cancelProviderFormTasks() {
        credentialSaveTask?.cancel()
        openRouterUsageTask?.cancel()
        codexAuthTask?.cancel()
        claudeManagedRefreshTask?.cancel()
    }
}
