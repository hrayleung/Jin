import SwiftUI

// MARK: - Credentials, API Key & Test Connection

extension ProviderConfigFormView {

    // MARK: - API Key Section

    var apiKeyField: some View {
        JinSettingsSecureFieldRow(
            apiKeyFieldTitle,
            text: $apiKey,
            isRevealed: $showingAPIKey,
            revealHelp: ProviderFormSupport.apiKeyRevealHelp(for: providerType),
            concealHelp: ProviderFormSupport.apiKeyConcealHelp(for: providerType)
        )
    }

    var apiKeyFieldTitle: String {
        ProviderFormSupport.apiKeyFieldTitle(for: providerType)
    }

    // MARK: - Vertex AI Section

    var vertexAISection: some View {
        JinSettingsBlockRow(
            "Service Account JSON",
            supportingText: "Paste the full JSON document for this service account."
        ) {
            JinSettingsTextEditor(
                text: $serviceAccountJSON,
                placeholder: "Paste JSON content here…",
                minHeight: 320
            )
        }
    }

    // MARK: - Test Connection Button

    var testConnectionButton: some View {
        HStack {
            Button("Test Connection") {
                testConnection()
            }
            .disabled(isTestDisabled)

            if testStatus == .testing {
                ProgressView().scaleEffect(0.5)
            }

            Spacer()

            switch testStatus {
            case .idle, .testing:
                EmptyView()
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Credential Actions

    func loadCredentials() async {
        await MainActor.run {
            guard let loadedProviderType = providerType else { return }

            switch ProviderFormSupport.credentialKind(for: loadedProviderType) {
            case .optionalAPIKey:
                let storedKey = provider.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                apiKey = storedKey
                if provider.apiKeyKeychainID == CodexLocalAuthStore.authModeHint {
                    codexAuthMode = .localCodex
                } else {
                    codexAuthMode = storedKey.isEmpty ? .chatGPT : .apiKey
                }
                codexAuthStatus = .idle
                codexAccount = nil
                codexRateLimit = nil
                codexPendingLoginID = nil
            case .apiKey:
                apiKey = provider.apiKey ?? ""
            case .serviceAccountJSON:
                serviceAccountJSON = provider.serviceAccountJSON ?? ""
            }
        }
    }

    func testConnection() {
        testStatus = .testing

        Task {
            do {
                try await saveCredentials()

                guard let config = try? provider.toDomain() else {
                    testStatus = .failure("Invalid configuration")
                    return
                }

                let isValid = try await providerManager.validateConfiguration(for: config)
                testStatus = isValid ? .success : .failure("Connection failed")
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
        }
    }

    func saveCredentials() async throws {
        credentialSaveTask?.cancel()
        credentialSaveTask = nil
        try await persistCredentials(validate: true)
    }

    func scheduleCredentialSave() {
        credentialSaveTask?.cancel()
        credentialSaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)

            do {
                try await persistCredentials(validate: false)
                await MainActor.run { credentialSaveError = nil }
            } catch {
                await MainActor.run { credentialSaveError = error.localizedDescription }
            }
        }
    }

    func persistCredentials(validate: Bool) async throws {
        guard let persistedProviderType = providerType else { return }

        switch ProviderFormSupport.credentialKind(for: persistedProviderType) {
        case .optionalAPIKey:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = codexAuthMode == .localCodex ? CodexLocalAuthStore.authModeHint : nil
                provider.apiKey = codexAuthMode == .apiKey ? ProviderFormSupport.normalizedOptionalString(key) : nil
                provider.serviceAccountJSON = nil
                try? modelContext.save()
            }

        case .apiKey:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if persistedProviderType != .claudeManagedAgents {
                    provider.apiKeyKeychainID = nil
                }
                provider.apiKey = ProviderFormSupport.normalizedOptionalString(key)
                provider.serviceAccountJSON = nil
                try? modelContext.save()
            }

        case .serviceAccountJSON:
            let json = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)

            if validate {
                _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
            }

            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.serviceAccountJSON = ProviderFormSupport.normalizedOptionalString(json)
                provider.apiKey = nil
                try? modelContext.save()
            }
        }
    }

    // MARK: - Helpers

    var isTestDisabled: Bool {
        ProviderFormSupport.isTestConnectionDisabled(
            providerType: providerType,
            codexCanUseCurrentAuthenticationMode: codexCanUseCurrentAuthenticationMode,
            codexAuthIsWorking: codexAuthStatus == .working,
            isTesting: testStatus == .testing,
            apiKey: apiKey,
            serviceAccountJSON: serviceAccountJSON
        )
    }
}
