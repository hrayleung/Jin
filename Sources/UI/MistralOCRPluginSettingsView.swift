import SwiftUI

struct MistralOCRPluginSettingsView: View {
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedAPIKey.isEmpty && !isSaving && !isTesting
    }

    var body: some View {
        Form {
            Section("Mistral OCR") {
                Text("Used to OCR PDFs when your selected model does not support native PDF reading, or when you choose OCR in the chat composer.")
                    .jinInfoCallout()
            }

            Section("API Key") {
                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)

                Text("Stored in Keychain. Unsigned builds (e.g. `swift run`) may prompt repeatedly; running from Xcode (signed) is smoother.")
                    .jinInfoCallout()

                HStack(spacing: 12) {
                    Button("Save") {
                        saveKey()
                    }
                    .disabled(!canSave)

                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(trimmedAPIKey.isEmpty || isSaving || isTesting)

                    Button("Clear", role: .destructive) {
                        clearKey()
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
        .navigationTitle("Mistral OCR")
        .task {
            await loadExistingKey()
        }
    }

    private func loadExistingKey() async {
        let keychainManager = KeychainManager()
        let existing = (try? await keychainManager.getAPIKey(for: MistralOCRClient.Constants.keychainID)) ?? ""
        await MainActor.run {
            apiKey = existing
        }
    }

    private func saveKey() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isSaving = true

        Task {
            do {
                let keychainManager = KeychainManager()
                try await keychainManager.saveAPIKey(trimmedAPIKey, for: MistralOCRClient.Constants.keychainID)
                await MainActor.run {
                    isSaving = false
                    statusMessage = "Saved."
                    statusIsError = false
                }
                NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func clearKey() {
        statusMessage = nil
        statusIsError = false
        isSaving = true

        Task {
            do {
                let keychainManager = KeychainManager()
                try await keychainManager.deleteAPIKey(for: MistralOCRClient.Constants.keychainID)
                await MainActor.run {
                    apiKey = ""
                    isSaving = false
                    statusMessage = "Cleared."
                    statusIsError = false
                }
                NotificationCenter.default.post(name: .pluginCredentialsDidChange, object: nil)
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func testConnection() {
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        statusIsError = false
        isTesting = true

        Task {
            do {
                let client = MistralOCRClient(apiKey: trimmedAPIKey)
                try await client.validateAPIKey()
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
}
