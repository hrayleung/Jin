import SwiftUI

struct UpdateSettingsView: View {
    @EnvironmentObject private var updateManager: SparkleUpdateManager

    @State private var checkError: String?

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

                if let error = checkError {
                    Text(error)
                        .jinInlineErrorText()
                }

                Toggle("Check automatically on launch", isOn: automaticallyChecksBinding)

                Toggle("Include pre-release versions", isOn: preReleaseBinding)

                if updateManager.allowPreRelease {
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
                .disabled(!updateManager.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .onAppear {
            checkError = nil
            updateManager.refreshPublishedProperties()
        }
    }

    private var automaticallyChecksBinding: Binding<Bool> {
        Binding(
            get: { updateManager.automaticallyChecksForUpdates },
            set: { updateManager.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var preReleaseBinding: Binding<Bool> {
        Binding(
            get: { updateManager.allowPreRelease },
            set: { updateManager.setAllowsPreReleaseUpdates($0) }
        )
    }

    private func runCheck() {
        guard updateManager.canCheckForUpdates else {
            checkError = "Update checks are currently unavailable"
            return
        }

        checkError = nil
        updateManager.triggerManualCheck()
    }
}
