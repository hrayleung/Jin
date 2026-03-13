import SwiftUI

// MARK: - Codex Sections & Actions

extension ProviderConfigFormView {

    var codexOverviewSection: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text("Jin talks to Codex App Server over WebSocket. Use this screen for provider-level setup, then tune per-chat sandbox, personality, and working directory from the chat toolbar.")
                .jinInfoCallout()
        }
        .padding(.vertical, 4)
    }

    var codexServerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(codexServerStatusColor)
                    .frame(width: 8, height: 8)
                Text(codexServerStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(codexServerStatusMessage)
                .foregroundStyle(.secondary)

            if let codexServerLaunchError {
                Text(codexServerLaunchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let lastLine = codexServerController.lastOutputLine, !lastLine.isEmpty {
                Text(lastLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if codexServerController.managedProcessCount > 0,
               case .stopped = codexServerController.status {
                Text("Detected \(codexServerController.managedProcessCount) Jin-managed Codex app-server process(es) still running. Use Force Stop to clean them up.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button {
                    startCodexServer()
                } label: {
                    Label("Start Server", systemImage: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(codexServerStartDisabled)

                Button {
                    stopCodexServer()
                } label: {
                    Label("Stop Server", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .disabled(codexServerStopDisabled)

                Button(role: .destructive) {
                    forceStopCodexServer()
                } label: {
                    Label("Force Stop", systemImage: "bolt.slash.fill")
                }
                .buttonStyle(.borderless)
                .disabled(codexServerForceStopDisabled)

                Button {
                    codexServerController.refreshManagedProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Jin-managed Codex process status")
            }
        }
        .padding(.vertical, 4)
    }

    var codexServerStatusLabel: String {
        switch codexServerController.status {
        case .stopped:
            return "Server stopped"
        case .starting:
            return "Server starting"
        case .running:
            return "Server running"
        case .stopping:
            return "Server stopping"
        case .failed:
            return "Server failed"
        }
    }

    var codexServerStatusColor: Color {
        switch codexServerController.status {
        case .running:
            return .green
        case .starting, .stopping:
            return .orange
        case .stopped:
            return .secondary
        case .failed:
            return .red
        }
    }

    var codexServerStatusMessage: String {
        if let validation = codexServerListenURLValidationError {
            return validation
        }

        switch codexServerController.status {
        case .running(let pid, let listenURL):
            return "`codex app-server` is running (pid \(pid)) on \(listenURL)"
        case .starting:
            return "Starting `codex app-server --listen \(codexServerListenURL)`..."
        case .stopping:
            return "Stopping `codex app-server`..."
        case .failed(let message):
            return message
        case .stopped:
            return "Ready to launch `codex app-server --listen \(codexServerListenURL)`."
        }
    }

    var codexServerStartDisabled: Bool {
        if codexServerListenURLValidationError != nil { return true }
        switch codexServerController.status {
        case .starting, .running, .stopping:
            return true
        case .stopped, .failed:
            return false
        }
    }

    var codexServerStopDisabled: Bool {
        switch codexServerController.status {
        case .running, .starting:
            return false
        case .stopped, .stopping, .failed:
            return true
        }
    }

    var codexServerForceStopDisabled: Bool {
        switch codexServerController.status {
        case .stopping, .failed:
            return false
        default:
            return !codexServerController.hasManagedProcesses
        }
    }

    var codexServerListenURL: String {
        let fallback = ProviderType.codexAppServer.defaultBaseURL ?? "ws://127.0.0.1:4500"
        let trimmed = (provider.baseURL ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var codexServerListenURLValidationError: String? {
        let listen = codexServerListenURL
        guard let parsed = URL(string: listen),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            return "Base URL must be a valid ws:// or wss:// listen address to launch app-server."
        }

        guard let host = parsed.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost" || host == "::1" else {
            return "In-app app-server launch only supports localhost listen addresses."
        }
        return nil
    }

    func startCodexServer() {
        codexServerLaunchError = nil

        if let validation = codexServerListenURLValidationError {
            codexServerLaunchError = validation
            return
        }

        do {
            try codexServerController.start(listenURL: codexServerListenURL)
        } catch {
            codexServerLaunchError = error.localizedDescription
        }
    }

    func stopCodexServer() {
        codexServerLaunchError = nil
        codexServerController.stop()
    }

    func forceStopCodexServer() {
        codexServerLaunchError = nil
        codexServerController.forceStopManagedServers()
    }

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

    var codexWorkingDirectoryPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: JinSpacing.small) {
                Label("Working Directory Presets", systemImage: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Manage…") {
                    codexWorkingDirectoryPresetsDraft = codexWorkingDirectoryPresets
                    showingCodexWorkingDirectoryPresetsSheet = true
                }
                .buttonStyle(.borderless)
            }

            if codexWorkingDirectoryPresets.isEmpty {
                Text("No presets configured.")
                    .jinInfoCallout()
            } else {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("\(codexWorkingDirectoryPresets.count) preset(s) available in chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: JinSpacing.xSmall) {
                            ForEach(codexWorkingDirectoryPresets.prefix(4)) { preset in
                                Text(preset.name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, JinSpacing.small)
                                    .padding(.vertical, 4)
                                    .jinSurface(.outlined, cornerRadius: JinRadius.small)
                            }
                            if codexWorkingDirectoryPresets.count > 4 {
                                Text("+\(codexWorkingDirectoryPresets.count - 4) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    var codexLocalAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let hasLocalKey = CodexLocalAuthStore.loadAPIKey() != nil
            let authPath = CodexLocalAuthStore.authFileURL().path

            HStack(spacing: 6) {
                Circle()
                    .fill(hasLocalKey ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(hasLocalKey ? "Local key available" : "No local key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Reusing the API key stored by your local Codex CLI in `\(authPath)`.")
                .foregroundStyle(.secondary)

            if !hasLocalKey {
                Text("No `OPENAI_API_KEY` found yet. Run `codex login` or update your local auth file first.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    var codexChatGPTAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(codexAuthStatusColor)
                    .frame(width: 8, height: 8)
                Text(codexAuthStatusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(codexAuthStatusMessage)
                .foregroundStyle(.secondary)

            if let codexRateLimit {
                Text(formatCodexRateLimit(codexRateLimit))
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
                .disabled(codexAuthStatus == .working)

                Button {
                    Task { await refreshCodexAccountStatus(forceRefreshToken: true) }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(codexAuthStatus == .working)

                Button(role: .destructive) {
                    disconnectCodexChatGPTAccount()
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .disabled(codexAuthStatus == .working || codexAccount?.isAuthenticated != true)

                if codexAuthStatus == .working {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
        }
        .padding(.vertical, 4)
    }

    var codexAuthStatusLabel: String {
        switch codexAuthStatus {
        case .idle:
            return "Not checked"
        case .working:
            return "Working"
        case .connected:
            return "Connected"
        case .failure:
            return "Failed"
        }
    }

    var codexAuthStatusColor: Color {
        switch codexAuthStatus {
        case .connected:
            return .green
        case .working:
            return .orange
        case .idle, .failure:
            return .secondary
        }
    }

    var codexAuthStatusMessage: String {
        switch codexAuthStatus {
        case .idle:
            return "Use Connect ChatGPT to open browser login."
        case .working:
            return "Waiting for ChatGPT account authorization..."
        case .connected:
            let name = codexAccount?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = codexAccount?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty, let email, !email.isEmpty {
                return "Logged in as \(name) (\(email))."
            }
            if let email, !email.isEmpty {
                return "Logged in as \(email)."
            }
            if let mode = codexAccount?.authMode, !mode.isEmpty {
                return "Account is authenticated via \(mode)."
            }
            return "Account is authenticated."
        case .failure(let message):
            return message
        }
    }

    func formatCodexRateLimit(_ rateLimit: CodexAppServerAdapter.RateLimitStatus) -> String {
        var parts: [String] = []
        parts.append("Rate limit: \(rateLimit.name)")

        if let usedPercentage = rateLimit.usedPercentage {
            parts.append("\(usedPercentage.formatted(.number.precision(.fractionLength(0...2))))% used")
        }
        if let windowMinutes = rateLimit.windowMinutes {
            parts.append("window \(windowMinutes)m")
        }
        if let resetsAt = rateLimit.resetsAt {
            parts.append("resets \(resetsAt.formatted(date: .omitted, time: .shortened))")
        }

        return parts.joined(separator: " · ")
    }

    var codexCanUseCurrentAuthenticationMode: Bool {
        switch codexAuthMode {
        case .apiKey:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .chatGPT:
            return codexAccount?.isAuthenticated == true && codexAuthStatus == .connected
        case .localCodex:
            return CodexLocalAuthStore.loadAPIKey() != nil
        }
    }

    // MARK: - Codex Working Directory Presets

    func loadCodexWorkingDirectoryPresets() {
        codexWorkingDirectoryPresets = CodexWorkingDirectoryPresetsStore.load()
    }

    func persistCodexWorkingDirectoryPresets() {
        CodexWorkingDirectoryPresetsStore.save(codexWorkingDirectoryPresets)
        codexWorkingDirectoryPresets = CodexWorkingDirectoryPresetsStore.load()
    }

    // MARK: - Codex Account Actions

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
