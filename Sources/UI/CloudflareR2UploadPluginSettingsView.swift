import SwiftUI

struct CloudflareR2UploadPluginSettingsView: View {
    @State private var accountID = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var bucket = ""
    @State private var publicBaseURL = ""
    @State private var keyPrefix = ""

    @State private var isSecretVisible = false
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

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

    private var canSave: Bool {
        !isSaving && !isTesting
    }

    private var canTest: Bool {
        draftConfiguration.missingRequiredFields.isEmpty && !isSaving && !isTesting
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

                Text("Credentials are stored locally on this device.")
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
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(!canSave)

                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!canTest)

                    Button("Clear", role: .destructive) {
                        clearSettings()
                    }
                    .disabled(isSaving || isTesting)

                    Spacer()

                    if isSaving || isTesting {
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
    }

    private func loadExistingSettings() async {
        let defaults = UserDefaults.standard
        await MainActor.run {
            accountID = defaults.string(forKey: AppPreferenceKeys.cloudflareR2AccountID) ?? ""
            accessKeyID = defaults.string(forKey: AppPreferenceKeys.cloudflareR2AccessKeyID) ?? ""
            secretAccessKey = defaults.string(forKey: AppPreferenceKeys.cloudflareR2SecretAccessKey) ?? ""
            bucket = defaults.string(forKey: AppPreferenceKeys.cloudflareR2Bucket) ?? ""
            publicBaseURL = defaults.string(forKey: AppPreferenceKeys.cloudflareR2PublicBaseURL) ?? ""
            keyPrefix = defaults.string(forKey: AppPreferenceKeys.cloudflareR2KeyPrefix) ?? ""
        }
    }

    private func saveSettings() {
        statusMessage = nil
        statusIsError = false
        isSaving = true

        let defaults = UserDefaults.standard
        persist(accountID, for: AppPreferenceKeys.cloudflareR2AccountID, defaults: defaults)
        persist(accessKeyID, for: AppPreferenceKeys.cloudflareR2AccessKeyID, defaults: defaults)
        persist(secretAccessKey, for: AppPreferenceKeys.cloudflareR2SecretAccessKey, defaults: defaults)
        persist(bucket, for: AppPreferenceKeys.cloudflareR2Bucket, defaults: defaults)
        persist(publicBaseURL, for: AppPreferenceKeys.cloudflareR2PublicBaseURL, defaults: defaults)
        persist(keyPrefix, for: AppPreferenceKeys.cloudflareR2KeyPrefix, defaults: defaults)

        isSaving = false
        statusMessage = "Saved."
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
    }

    private func clearSettings() {
        statusMessage = nil
        statusIsError = false
        isSaving = true

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppPreferenceKeys.cloudflareR2AccountID)
        defaults.removeObject(forKey: AppPreferenceKeys.cloudflareR2AccessKeyID)
        defaults.removeObject(forKey: AppPreferenceKeys.cloudflareR2SecretAccessKey)
        defaults.removeObject(forKey: AppPreferenceKeys.cloudflareR2Bucket)
        defaults.removeObject(forKey: AppPreferenceKeys.cloudflareR2PublicBaseURL)
        defaults.removeObject(forKey: AppPreferenceKeys.cloudflareR2KeyPrefix)

        accountID = ""
        accessKeyID = ""
        secretAccessKey = ""
        bucket = ""
        publicBaseURL = ""
        keyPrefix = ""

        isSaving = false
        statusMessage = "Cleared."
        statusIsError = false
        NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
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
}
