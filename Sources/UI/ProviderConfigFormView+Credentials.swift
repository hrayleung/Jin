import SwiftUI

// MARK: - Credentials, API Key & Test Connection

extension ProviderConfigFormView {

    // MARK: - API Key Section

    var apiKeyField: some View {
        HStack(spacing: 8) {
            Group {
                if showingAPIKey {
                    TextField(apiKeyFieldTitle, text: $apiKey)
                } else {
                    SecureField(apiKeyFieldTitle, text: $apiKey)
                }
            }
            Button {
                showingAPIKey.toggle()
            } label: {
                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(showingAPIKey ? "Hide API key" : "Show API key")
            .disabled(apiKey.isEmpty)
        }
    }

    var apiKeyFieldTitle: String {
        providerType == .githubCopilot ? "GitHub Token" : "API Key"
    }

    // MARK: - Vertex AI Section

    var vertexAISection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Service Account JSON")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $serviceAccountJSON)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .jinTextEditorField(cornerRadius: JinRadius.small)
                .overlay(alignment: .topLeading) {
                    if serviceAccountJSON.isEmpty {
                        Text("Paste JSON content here…")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
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
            switch ProviderType(rawValue: provider.typeRaw) {
            case .codexAppServer:
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
            case .githubCopilot:
                apiKey = provider.apiKey ?? ""
            case .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
                 .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai,
                 .deepseek, .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .gemini:
                apiKey = provider.apiKey ?? ""
            case .vertexai:
                serviceAccountJSON = provider.serviceAccountJSON ?? ""
            case .none:
                break
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
        switch ProviderType(rawValue: provider.typeRaw) {
        case .codexAppServer:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = codexAuthMode == .localCodex ? CodexLocalAuthStore.authModeHint : nil
                provider.apiKey = (codexAuthMode == .apiKey && !key.isEmpty) ? key : nil
                provider.serviceAccountJSON = nil
                try? modelContext.save()
            }

        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .gemini:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.apiKey = key.isEmpty ? nil : key
                provider.serviceAccountJSON = nil
                try? modelContext.save()
            }

        case .vertexai:
            let json = serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines)

            if validate {
                _ = try JSONDecoder().decode(ServiceAccountCredentials.self, from: Data(json.utf8))
            }

            await MainActor.run {
                provider.apiKeyKeychainID = nil
                provider.serviceAccountJSON = json.isEmpty ? nil : json
                provider.apiKey = nil
                try? modelContext.save()
            }

        case .none:
            break
        }
    }

    // MARK: - Helpers

    var isTestDisabled: Bool {
        switch ProviderType(rawValue: provider.typeRaw) {
        case .codexAppServer:
            return !codexCanUseCurrentAuthenticationMode || testStatus == .testing || codexAuthStatus == .working
        case .githubCopilot, .openai, .openaiWebSocket, .openaiCompatible, .cloudflareAIGateway, .vercelAIGateway, .openrouter,
             .anthropic, .perplexity, .groq, .cohere, .mistral, .deepinfra, .together, .xai, .deepseek,
             .zhipuCodingPlan, .minimax, .minimaxCodingPlan, .fireworks, .cerebras, .sambanova, .morphllm, .gemini:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testStatus == .testing
        case .vertexai:
            return serviceAccountJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testStatus == .testing
        case .none:
            return true
        }
    }
}
