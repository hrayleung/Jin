import SwiftUI
import AppKit

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
        JinSettingsPage {
            UpdateSettingsVersionHero(
                version: currentVersion,
                build: currentBuild,
                allowPreRelease: updateManager.allowPreRelease,
                lastCheckDate: updateManager.lastUpdateCheckDate,
                canCheckForUpdates: updateManager.canCheckForUpdates,
                sessionInProgress: updateManager.sessionInProgress,
                checkError: checkError,
                onCheckForUpdates: runCheck
            )

            UpdateSettingsAutomaticSection(
                isOn: automaticallyChecksBinding
            )

            UpdateSettingsChannelSection(
                allowPreRelease: preReleaseBinding
            )
        }
        .navigationTitle("Updates")
        .onAppear {
            checkError = nil
            updateManager.refreshPublishedProperties()
        }
        .task(id: updateManager.sessionInProgress) {
            guard updateManager.sessionInProgress else { return }
            while !Task.isCancelled {
                updateManager.refreshPublishedProperties()
                if !updateManager.sessionInProgress { break }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
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
            checkError = "Update checks are currently unavailable."
            return
        }

        checkError = nil
        updateManager.triggerManualCheck()
        updateManager.refreshPublishedProperties()
    }
}
