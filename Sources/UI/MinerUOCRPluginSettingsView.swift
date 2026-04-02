import SwiftUI

struct MinerUOCRPluginSettingsView: View {
    private struct LanguageOption: Identifiable {
        let code: String
        let label: String

        var id: String { code }
    }

    private static let languageOptions: [LanguageOption] = [
        .init(code: "ch", label: "Chinese + English (ch)"),
        .init(code: "ch_server", label: "Chinese Server (ch_server)"),
        .init(code: "en", label: "English (en)"),
        .init(code: "japan", label: "Japanese (japan)"),
        .init(code: "korean", label: "Korean (korean)"),
        .init(code: "chinese_cht", label: "Traditional Chinese (cht)"),
        .init(code: "ta", label: "Tamil (ta)"),
        .init(code: "te", label: "Telugu (te)"),
        .init(code: "ka", label: "Kannada (ka)"),
        .init(code: "el", label: "Greek (el)"),
        .init(code: "th", label: "Thai (th)")
    ]

    @State private var apiToken = ""
    @State private var userIdentifier = ""
    @State private var selectedLanguage = MinerUOCRClient.Constants.defaultLanguage
    @State private var isTokenVisible = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hasLoadedSettings = false
    @State private var lastPersistedToken = ""
    @State private var lastPersistedUserIdentifier = ""
    @State private var lastPersistedLanguage = MinerUOCRClient.Constants.defaultLanguage
    @State private var autoSaveTask: Task<Void, Never>?

    private var trimmedToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUserIdentifier: String {
        userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("API Token") {
                HStack(spacing: 8) {
                    Group {
                        if isTokenVisible {
                            TextField("MinerU API Token", text: $apiToken)
                                .textContentType(.password)
                        } else {
                            SecureField("MinerU API Token", text: $apiToken)
                                .textContentType(.password)
                        }
                    }

                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(isTokenVisible ? "Hide API token" : "Show API token")
                    .disabled(apiToken.isEmpty)
                }

                TextField("Optional user header", text: $userIdentifier)

                HStack(spacing: 12) {
                    Button("Check Token") { runTestConnection() }
                        .disabled(trimmedToken.isEmpty || isTesting)

                    Button("Clear", role: .destructive) { clearSettings() }
                        .disabled(isTesting)

                    Spacer()

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                }
            }

            Section("OCR") {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(Self.languageOptions) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("MinerU OCR")
        .task {
            await loadExistingSettings()
            hasLoadedSettings = true
        }
        .onChange(of: apiToken) { _, _ in scheduleAutoSave() }
        .onChange(of: userIdentifier) { _, _ in scheduleAutoSave() }
        .onChange(of: selectedLanguage) { _, _ in scheduleAutoSave() }
        .onDisappear {
            autoSaveTask?.cancel()
        }
    }

    private func loadExistingSettings() async {
        let defaults = UserDefaults.standard
        let existingToken = defaults.string(forKey: AppPreferenceKeys.pluginMineruOCRAPIToken) ?? ""
        let existingUserIdentifier = defaults.string(forKey: AppPreferenceKeys.pluginMineruOCRUserIdentifier) ?? ""
        let existingLanguage = defaults.string(forKey: AppPreferenceKeys.pluginMineruOCRLanguage)
            ?? MinerUOCRClient.Constants.defaultLanguage

        await MainActor.run {
            apiToken = existingToken
            userIdentifier = existingUserIdentifier
            selectedLanguage = existingLanguage
            lastPersistedToken = existingToken.trimmingCharacters(in: .whitespacesAndNewlines)
            lastPersistedUserIdentifier = existingUserIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            lastPersistedLanguage = existingLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func scheduleAutoSave() {
        guard hasLoadedSettings else { return }
        autoSaveTask?.cancel()

        let nextToken = trimmedToken
        let nextUserIdentifier = trimmedUserIdentifier
        let nextLanguage = selectedLanguage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard nextToken != lastPersistedToken
            || nextUserIdentifier != lastPersistedUserIdentifier
            || nextLanguage != lastPersistedLanguage else {
            return
        }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistSettings(
                    token: nextToken,
                    userIdentifier: nextUserIdentifier,
                    language: nextLanguage.isEmpty ? MinerUOCRClient.Constants.defaultLanguage : nextLanguage
                )
            }
        }
    }

    private func persistSettings(token: String, userIdentifier: String, language: String) {
        let defaults = UserDefaults.standard
        if token.isEmpty {
            defaults.removeObject(forKey: AppPreferenceKeys.pluginMineruOCRAPIToken)
        } else {
            defaults.set(token, forKey: AppPreferenceKeys.pluginMineruOCRAPIToken)
        }

        if userIdentifier.isEmpty {
            defaults.removeObject(forKey: AppPreferenceKeys.pluginMineruOCRUserIdentifier)
        } else {
            defaults.set(userIdentifier, forKey: AppPreferenceKeys.pluginMineruOCRUserIdentifier)
        }

        defaults.set(language, forKey: AppPreferenceKeys.pluginMineruOCRLanguage)

        lastPersistedToken = token
        lastPersistedUserIdentifier = userIdentifier
        lastPersistedLanguage = language
        statusMessage = token.isEmpty ? "Cleared." : "Saved automatically."
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func clearSettings() {
        autoSaveTask?.cancel()
        apiToken = ""
        userIdentifier = ""
        selectedLanguage = MinerUOCRClient.Constants.defaultLanguage
        persistSettings(token: "", userIdentifier: "", language: MinerUOCRClient.Constants.defaultLanguage)
    }

    private func runTestConnection() {
        guard !trimmedToken.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        let token = trimmedToken
        let userIdentifier = trimmedUserIdentifier
        let language = selectedLanguage

        Task {
            do {
                let client = MinerUOCRClient(
                    apiToken: token,
                    userToken: userIdentifier.isEmpty ? nil : userIdentifier
                )
                try await client.validateAPIKey(language: language)
                await MainActor.run {
                    isTesting = false
                    statusMessage = "Token verified."
                    statusIsError = false
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }
}
