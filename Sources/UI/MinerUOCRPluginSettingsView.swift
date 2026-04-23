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
    @State private var validationTask: Task<Void, Never>?

    private var trimmedToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUserIdentifier: String {
        userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        JinSettingsPage {
            JinSettingsSection(
                "API Token",
                detail: "MinerU uses a token plus an optional user header. Changes save automatically."
            ) {
                JinSettingsControlRow(
                    "API Token",
                    supportingText: "Stored locally on this Mac. Changes save automatically."
                ) {
                    JinRevealableSecureField(
                        title: "MinerU API Token",
                        text: $apiToken,
                        isRevealed: $isTokenVisible,
                        revealHelp: "Show API token",
                        concealHelp: "Hide API token"
                    )
                }

                JinSettingsControlRow(
                    "User Header",
                    supportingText: "Optional. Sends an extra user identifier with requests."
                ) {
                    TextField("Optional user header", text: $userIdentifier)
                        .textFieldStyle(.roundedBorder)
                }

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
                    JinSettingsStatusText(text: statusMessage, isError: statusIsError)
                }
            }

            JinSettingsSection("OCR") {
                JinSettingsControlRow("Language") {
                    Picker("Language", selection: $selectedLanguage) {
                        ForEach(Self.languageOptions) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
            validationTask?.cancel()
            validationTask = nil
        }
    }

    private func loadExistingSettings() async {
        let defaults = UserDefaults.standard
        let existingToken = PreferenceSecretStore.loadSecret(
            forKey: AppPreferenceKeys.pluginMineruOCRAPIToken,
            defaults: defaults
        )
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
        do {
            try PreferenceSecretStore.saveSecret(
                token,
                forKey: AppPreferenceKeys.pluginMineruOCRAPIToken,
                defaults: defaults
            )
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            return
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

        validationTask?.cancel()
        statusMessage = nil
        statusIsError = false
        isTesting = true

        let token = trimmedToken
        let userIdentifier = trimmedUserIdentifier
        let language = selectedLanguage

        validationTask = Task {
            do {
                let client = MinerUOCRClient(
                    apiToken: token,
                    userToken: userIdentifier.isEmpty ? nil : userIdentifier
                )
                try await client.validateAPIKey(language: language)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isTesting = false
                    statusMessage = "Token verified."
                    statusIsError = false
                    validationTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isTesting = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                    validationTask = nil
                }
            }
        }
    }
}
