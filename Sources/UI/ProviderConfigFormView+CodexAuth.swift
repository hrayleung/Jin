import SwiftUI

extension ProviderConfigFormView {
    var codexAuthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Authentication", selection: $codexAuthMode) {
                Text("ChatGPT").tag(CodexAuthMode.chatGPT)
                Text("API Key").tag(CodexAuthMode.apiKey)
                Text("Use Codex Login").tag(CodexAuthMode.localCodex)
            }
            .pickerStyle(.segmented)

            switch codexAuthMode {
            case .apiKey:
                apiKeyField
            case .chatGPT:
                codexChatGPTAccountSection
            case .localCodex:
                codexLocalAuthSection
            }
        }
    }

    var codexLocalAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let hasLocalKey = CodexLocalAuthStore.loadAPIKey() != nil
            let authPath = CodexLocalAuthStore.authFileURL().path
            let presentation = CodexAppServerFormSupport.localAuthPresentation(
                hasLocalKey: hasLocalKey,
                authPath: authPath
            )

            HStack(spacing: 6) {
                Circle()
                    .fill(presentation.tone.color)
                    .frame(width: 8, height: 8)
                Text(presentation.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.message)
                .foregroundStyle(.secondary)

            if let missingKeyMessage = presentation.missingKeyMessage {
                Text(missingKeyMessage)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    var codexChatGPTAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let presentation = codexAuthStatusPresentation
            let buttonState = codexAuthButtonState

            HStack(spacing: 6) {
                Circle()
                    .fill(presentation.tone.color)
                    .frame(width: 8, height: 8)
                Text(presentation.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(presentation.message)
                .foregroundStyle(.secondary)

            if let codexRateLimit {
                Text(CodexAppServerFormSupport.rateLimitText(codexRateLimit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    connectCodexChatGPTAccount()
                } label: {
                    Label("Connect ChatGPT", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderless)
                .disabled(buttonState.connectDisabled)

                Button {
                    Task { await refreshCodexAccountStatus(forceRefreshToken: true) }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(buttonState.refreshDisabled)

                Button(role: .destructive) {
                    disconnectCodexChatGPTAccount()
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .disabled(buttonState.logoutDisabled)

                if codexAuthStatus == .working {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var codexAuthStatusPresentation: CodexAppServerFormSupport.StatusPresentation {
        CodexAppServerFormSupport.authStatusPresentation(
            status: codexAuthStatus,
            account: codexAccount
        )
    }

    var codexAuthButtonState: CodexAppServerFormSupport.AuthButtonState {
        CodexAppServerFormSupport.authButtonState(
            status: codexAuthStatus,
            isAuthenticated: codexAccount?.isAuthenticated == true
        )
    }

    var codexCanUseCurrentAuthenticationMode: Bool {
        CodexAppServerFormSupport.canUseAuthenticationMode(
            mode: codexAuthMode,
            apiKey: apiKey,
            status: codexAuthStatus,
            isAuthenticated: codexAccount?.isAuthenticated == true,
            hasLocalKey: CodexLocalAuthStore.loadAPIKey() != nil
        )
    }

    func connectCodexChatGPTAccount() {
        codexAuthTask?.cancel()
        codexAuthTask = Task {
            await MainActor.run {
                codexAuthStatus = .working
                codexPendingLoginID = nil
            }

            do {
                try await saveCredentials()
                let adapter = try codexAdapterForCurrentState()
                let challenge = try await adapter.startChatGPTLogin()
                await MainActor.run {
                    codexPendingLoginID = challenge.loginID
                    openURL(challenge.authURL)
                }

                try await waitForCodexChatGPTAuthentication(
                    adapter: adapter,
                    loginID: challenge.loginID,
                    timeoutSeconds: 180
                )
                await refreshCodexAccountStatus(forceRefreshToken: true)
            } catch is CancellationError {
                if let loginID = await MainActor.run(body: { codexPendingLoginID }) {
                    try? await codexAdapterForCurrentState().cancelChatGPTLogin(loginID: loginID)
                }
            } catch {
                await MainActor.run {
                    codexAuthStatus = .failure(error.localizedDescription)
                }
            }
        }
    }

    func disconnectCodexChatGPTAccount() {
        codexAuthTask?.cancel()
        codexAuthTask = Task {
            await MainActor.run { codexAuthStatus = .working }
            do {
                try await saveCredentials()
                try await codexAdapterForCurrentState().logoutAccount()
                await MainActor.run {
                    codexAccount = nil
                    codexRateLimit = nil
                    codexPendingLoginID = nil
                    codexAuthStatus = .idle
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    codexAuthStatus = .failure(error.localizedDescription)
                }
            }
        }
    }

    func refreshCodexAccountStatus(forceRefreshToken: Bool) async {
        guard providerType == .codexAppServer, codexAuthMode == .chatGPT else { return }
        await MainActor.run { codexAuthStatus = .working }

        do {
            try await saveCredentials()
            let adapter = try codexAdapterForCurrentState()
            let status = try await adapter.readAccountStatus(refreshToken: forceRefreshToken)
            let rateLimit = try? await adapter.readPrimaryRateLimit()
            await MainActor.run {
                codexAccount = status
                codexRateLimit = rateLimit
                codexPendingLoginID = nil
                codexAuthStatus = status.isAuthenticated ? .connected : .idle
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                codexAccount = nil
                codexRateLimit = nil
                codexAuthStatus = .failure(error.localizedDescription)
            }
        }
    }

    func waitForCodexChatGPTAuthentication(
        adapter: CodexAppServerAdapter,
        loginID: String,
        timeoutSeconds: Int
    ) async throws {
        _ = try await adapter.waitForChatGPTLoginCompletion(
            loginID: loginID,
            timeoutSeconds: timeoutSeconds
        )
    }

    func codexAdapterForCurrentState() throws -> CodexAppServerAdapter {
        guard providerType == .codexAppServer else {
            throw LLMError.invalidRequest(message: "Current provider is not Codex App Server.")
        }

        let key: String
        switch codexAuthMode {
        case .apiKey:
            key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .chatGPT:
            key = ""
        case .localCodex:
            guard let localKey = CodexLocalAuthStore.loadAPIKey() else {
                throw LLMError.invalidRequest(
                    message: "No OPENAI_API_KEY found in \(CodexLocalAuthStore.authFileURL().path)."
                )
            }
            key = localKey
        }

        let config = ProviderConfig(
            id: provider.id,
            name: provider.name,
            type: .codexAppServer,
            iconID: provider.iconID,
            authModeHint: codexAuthMode == .localCodex ? CodexLocalAuthStore.authModeHint : nil,
            apiKey: key.isEmpty ? nil : key,
            serviceAccountJSON: nil,
            baseURL: provider.baseURL,
            models: decodedModels
        )

        return CodexAppServerAdapter(providerConfig: config, apiKey: key, networkManager: networkManager)
    }
}
