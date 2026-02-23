import SwiftUI

struct UpdateSettingsView: View {
    @EnvironmentObject private var updateManager: SparkleUpdateManager

    @State private var isCheckingForUpdate = false
    @State private var checkError: String?

    @AppStorage(AppPreferenceKeys.updateAutoCheckOnLaunch) private var autoCheckOnLaunch = true
    @AppStorage(AppPreferenceKeys.updateAllowPreRelease) private var allowPreRelease = false

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var currentBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    var body: some View {
        Form {
            Section("Update Check") {
                LabeledContent("Current Version") {
                    Text(currentVersion)
                        .foregroundStyle(.secondary)
                }

                if let build = currentBuild {
                    LabeledContent("Build") {
                        Text(build)
                            .foregroundStyle(.secondary)
                    }
                }

                if isCheckingForUpdate {
                    HStack(spacing: JinSpacing.small) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = checkError {
                    Text(error)
                        .jinInlineErrorText()
                }

                Toggle("Check automatically on launch", isOn: $autoCheckOnLaunch)
                    .onChange(of: autoCheckOnLaunch) { _, value in
                        updateManager.setAutomaticallyChecksForUpdates(value)
                    }

                Toggle("Include pre-release versions", isOn: $allowPreRelease)
                    .onChange(of: allowPreRelease) { _, value in
                        updateManager.setAllowsPreReleaseUpdates(value)
                    }

                if allowPreRelease {
                    Text("Pre-release updates are delivered through the beta channel and may be unstable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    runCheck()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingForUpdate)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .onAppear {
            checkError = nil
            syncFromStorage()
            syncFromUpdater()
        }
    }

    private func runCheck() {
        guard updateManager.canCheckForUpdates else {
            checkError = "Update checks are currently unavailable"
            return
        }

        isCheckingForUpdate = true
        checkError = nil

        Task {
            await MainActor.run {
                updateManager.triggerManualCheck()
                isCheckingForUpdate = false
            }
        }
    }

    private func syncFromStorage() {
        if let value = UserDefaults.standard.object(forKey: AppPreferenceKeys.updateAutoCheckOnLaunch) as? Bool {
            autoCheckOnLaunch = value
        }

        if let value = UserDefaults.standard.object(forKey: AppPreferenceKeys.updateAllowPreRelease) as? Bool {
            allowPreRelease = value
        }
    }

    private func syncFromUpdater() {
        autoCheckOnLaunch = updateManager.automaticallyChecksForUpdates
        allowPreRelease = updateManager.allowPreRelease
    }
}
