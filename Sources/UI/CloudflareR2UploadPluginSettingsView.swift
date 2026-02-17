import SwiftUI

struct CloudflareR2UploadPluginSettingsView: View {
    @State private var accountID = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var bucket = ""
    @State private var publicBaseURL = ""
    @State private var keyPrefix = ""

    @State private var isSecretVisible = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var hasLoadedSettings = false
    @State private var lastPersistedConfiguration = CloudflareR2Configuration(
        accountID: "",
        accessKeyID: "",
        secretAccessKey: "",
        bucket: "",
        publicBaseURL: "",
        keyPrefix: ""
    )
    @State private var autoSaveTask: Task<Void, Never>?

    private var draftConfiguration: CloudflareR2Configuration {
        CloudflareR2Configuration(
            accountID: accountID,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            bucket: bucket,
            publicBaseURL: publicBaseURL,
            keyPrefix: keyPrefix
        )
    }

    private var canTest: Bool {
        draftConfiguration.missingRequiredFields.isEmpty && !isTesting
    }

    var body: some View {
        Form {
            Section("Cloudflare R2 Upload") {
                Text("Uploads local video attachments to your Cloudflare R2 bucket and passes the generated public URL to providers that require remote video input.")
                    .jinInfoCallout()
            }

            Section("Credentials") {
                TextField("Account ID", text: $accountID)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Access Key ID", text: $accessKeyID)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Group {
                        if isSecretVisible {
                            TextField("Secret Access Key", text: $secretAccessKey)
                                .textContentType(.password)
                        } else {
                            SecureField("Secret Access Key", text: $secretAccessKey)
                                .textContentType(.password)
                        }
                    }

                    Button {
                        isSecretVisible.toggle()
                    } label: {
                        Image(systemName: isSecretVisible ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(isSecretVisible ? "Hide secret key" : "Show secret key")
                    .disabled(secretAccessKey.isEmpty)
                }

                Text("Credentials are stored locally on this device and saved automatically while you type.")
                    .jinInfoCallout()
            }

            Section("Storage") {
                TextField("Bucket", text: $bucket)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Public Base URL (e.g. https://pub-xxx.r2.dev)", text: $publicBaseURL)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                TextField("Key Prefix (optional)", text: $keyPrefix)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            Section("Actions") {
                HStack(spacing: 12) {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!canTest)

                    Button("Clear", role: .destructive) {
                        clearSettings()
                    }
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .navigationTitle("Cloudflare R2 Upload")
        .task {
            await loadExistingSettings()
        }
        .onChange(of: accountID) { _, _ in scheduleAutoSaveIfNeeded() }
        .onChange(of: accessKeyID) { _, _ in scheduleAutoSaveIfNeeded() }
        .onChange(of: secretAccessKey) { _, _ in scheduleAutoSaveIfNeeded() }
        .onChange(of: bucket) { _, _ in scheduleAutoSaveIfNeeded() }
        .onChange(of: publicBaseURL) { _, _ in scheduleAutoSaveIfNeeded() }
        .onChange(of: keyPrefix) { _, _ in scheduleAutoSaveIfNeeded() }
        .onDisappear {
            autoSaveTask?.cancel()
        }
    }

    private func loadExistingSettings() async {
        let loaded = CloudflareR2Configuration.load(from: .standard)
        await MainActor.run {
            hasLoadedSettings = false
            applyConfigurationToState(loaded)
            lastPersistedConfiguration = loaded
            hasLoadedSettings = true
        }
    }

    private func clearSettings() {
        autoSaveTask?.cancel()
        statusMessage = nil
        statusIsError = false

        let empty = CloudflareR2Configuration(
            accountID: "",
            accessKeyID: "",
            secretAccessKey: "",
            bucket: "",
            publicBaseURL: "",
            keyPrefix: ""
        )
        persistConfiguration(empty, showSavedStatus: false)
        hasLoadedSettings = false
        applyConfigurationToState(empty)
        hasLoadedSettings = true
        statusMessage = "Cleared."
        statusIsError = false
    }

    private func testConnection() {
        statusMessage = nil
        statusIsError = false

        let configuration: CloudflareR2Configuration
        do {
            configuration = try draftConfiguration.validated()
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            return
        }

        isTesting = true

        Task {
            do {
                let uploader = CloudflareR2Uploader()
                try await uploader.testConnection(configuration: configuration)
                await MainActor.run {
                    isTesting = false
                    statusMessage = "Connection OK."
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

    private func persist(_ rawValue: String, for key: String, defaults: UserDefaults) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    private func scheduleAutoSaveIfNeeded() {
        guard hasLoadedSettings else { return }

        autoSaveTask?.cancel()
        let configuration = draftConfiguration
        guard configuration != lastPersistedConfiguration else { return }

        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistConfiguration(configuration, showSavedStatus: true)
            }
        }
    }

    private func persistConfiguration(_ configuration: CloudflareR2Configuration, showSavedStatus: Bool) {
        guard configuration != lastPersistedConfiguration else { return }

        let defaults = UserDefaults.standard
        persist(configuration.accountID, for: AppPreferenceKeys.cloudflareR2AccountID, defaults: defaults)
        persist(configuration.accessKeyID, for: AppPreferenceKeys.cloudflareR2AccessKeyID, defaults: defaults)
        persist(configuration.secretAccessKey, for: AppPreferenceKeys.cloudflareR2SecretAccessKey, defaults: defaults)
        persist(configuration.bucket, for: AppPreferenceKeys.cloudflareR2Bucket, defaults: defaults)
        persist(configuration.publicBaseURL, for: AppPreferenceKeys.cloudflareR2PublicBaseURL, defaults: defaults)
        persist(configuration.keyPrefix, for: AppPreferenceKeys.cloudflareR2KeyPrefix, defaults: defaults)

        lastPersistedConfiguration = configuration
        if showSavedStatus {
            statusMessage = configurationIsEmpty(configuration) ? "Cleared." : "Saved automatically."
            statusIsError = false
        }
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func applyConfigurationToState(_ configuration: CloudflareR2Configuration) {
        accountID = configuration.accountID
        accessKeyID = configuration.accessKeyID
        secretAccessKey = configuration.secretAccessKey
        bucket = configuration.bucket
        publicBaseURL = configuration.publicBaseURL
        keyPrefix = configuration.keyPrefix
    }

    private func configurationIsEmpty(_ configuration: CloudflareR2Configuration) -> Bool {
        configuration.accountID.isEmpty
            && configuration.accessKeyID.isEmpty
            && configuration.secretAccessKey.isEmpty
            && configuration.bucket.isEmpty
            && configuration.publicBaseURL.isEmpty
            && configuration.keyPrefix.isEmpty
    }
}
