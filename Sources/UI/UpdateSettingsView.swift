import SwiftUI
import AppKit

struct UpdateSettingsView: View {
    @State private var isCheckingForUpdate = false
    @State private var isInstallingUpdate = false
    @State private var checkError: String?
    @State private var lastResult: GitHubReleaseCandidate?
    @State private var lastCheckedAt: Date?
    @State private var installStatusMessage: String?

    @AppStorage(AppPreferenceKeys.updateAutoCheckOnLaunch) private var autoCheckOnLaunch = true
    @AppStorage(AppPreferenceKeys.updateAllowPreRelease) private var allowPreRelease = false
    @AppStorage(AppPreferenceKeys.updateInstalledVersion) private var installedVersion = ""

    private var currentVersion: String {
        GitHubReleaseChecker.resolveCurrentVersion(
            bundleVersion: GitHubReleaseChecker.currentVersion(from: .main),
            currentInstalledVersion: installedVersion
        ) ?? "Unknown"
    }

    private var isVersionSyncedWithBundle: Bool {
        guard let bundleVersion = GitHubReleaseChecker.currentVersion(from: .main) else {
            return false
        }

        return bundleVersion == installedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            || installedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let releaseRepository = GitHubReleaseChecker.defaultRepository

    var body: some View {
        Form {
            Section("Update Check") {
                LabeledContent("Current Version") {
                    Text(currentVersion)
                        .foregroundStyle(.secondary)
                }

                if !isVersionSyncedWithBundle {
                    Text("Current version differs from this app bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Sync Current Version") {
                        syncCurrentVersion()
                    }
                    .buttonStyle(.borderless)
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

                if isInstallingUpdate {
                    HStack(spacing: JinSpacing.small) {
                        ProgressView()
                            .controlSize(.small)
                        Text(installStatusMessage ?? "Preparing update…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let checkedAt = lastCheckedAt {
                    LabeledContent("Last Checked") {
                        Text(checkedAt.formatted(date: .numeric, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = checkError {
                    Text(error)
                        .jinInlineErrorText()
                }

                Toggle("Check automatically on launch", isOn: $autoCheckOnLaunch)

                Toggle("Include pre-release versions", isOn: $allowPreRelease)

                if allowPreRelease {
                    Text("Pre-release versions may include feature-complete but unstable builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await runCheck()
                    }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingForUpdate || isInstallingUpdate)
            }

            if let result = lastResult {
                Section("Latest Release") {
                    LabeledContent("Version") {
                        Text(result.tagName)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Release") {
                        Text(result.releaseTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let publishedAt = result.publishedAt {
                        LabeledContent("Published") {
                            Text(publishedAt.formatted(date: .numeric, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if result.isPrerelease {
                        Text("This release is marked as pre-release.")
                            .jinInfoCallout()
                            .foregroundStyle(.secondary)
                    }

                    if result.isUpdateAvailable {
                        Text("A newer version is available.")
                            .jinInfoCallout()
                            .foregroundStyle(.secondary)

                        Text("Download Asset")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)

                        Text(result.asset.name)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: JinSpacing.small) {
                            Button {
                                Task {
                                    await installAndRelaunchUpdate(result)
                                }
                            } label: {
                                Label("Install & Relaunch", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInstallingUpdate || isCheckingForUpdate)

                            Button {
                                NSWorkspace.shared.open(result.asset.downloadURL)
                            } label: {
                                Label("Download Manually", systemImage: "arrow.down.doc")
                            }
                            .disabled(isInstallingUpdate)

                            if let url = result.htmlURL {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("Release Page", systemImage: "link")
                                }
                                .disabled(isInstallingUpdate)
                            }
                        }
                    } else {
                        Text("You are already on the latest known release.")
                            .jinInfoCallout()
                            .foregroundStyle(.secondary)

                        if let url = result.htmlURL {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("Open Release Page", systemImage: "link")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if !result.body.isEmpty {
                        DisclosureGroup("Release Notes") {
                            Text(result.body)
                                .font(.system(.footnote))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(JinSemanticColor.detailSurface)
        .onAppear {
            syncCurrentVersion()
            checkError = nil
            lastResult = nil
        }
    }

    @MainActor
    private func runCheck() async {
        guard !isInstallingUpdate else { return }
        isCheckingForUpdate = true
        checkError = nil
        lastResult = nil
        defer {
            isCheckingForUpdate = false
            lastCheckedAt = Date()
        }

        do {
            let currentInstalledVersion = syncCurrentVersion()
            let result = try await GitHubReleaseChecker.checkForUpdate(
                repository: releaseRepository,
                currentInstalledVersion: currentInstalledVersion,
                allowPreRelease: allowPreRelease
            )
            lastResult = result
        } catch {
            checkError = error.localizedDescription
        }
    }

    @MainActor
    private func installAndRelaunchUpdate(_ result: GitHubReleaseCandidate) async {
        guard !isInstallingUpdate else { return }
        checkError = nil
        installStatusMessage = "Downloading update…"
        isInstallingUpdate = true

        do {
            let appNameHint = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
            let preparedUpdate = try await GitHubAutoUpdater.prepareUpdate(
                from: result.asset,
                appNameHint: appNameHint
            )
            installStatusMessage = "Installing update and restarting…"
            try GitHubAutoUpdater.launchInstaller(using: preparedUpdate)
            NSApp.terminate(nil)
        } catch {
            isInstallingUpdate = false
            installStatusMessage = nil
            checkError = error.localizedDescription
        }
    }

    @discardableResult
    private func syncCurrentVersion() -> String? {
        let bundleVersion = GitHubReleaseChecker.currentVersion(from: .main)
        if let bundleVersion {
            installedVersion = bundleVersion
        } else if !installedVersion.isEmpty {
            installedVersion = installedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return installedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : installedVersion
    }
}
