//
//  SparkleUpdateManager.swift
//
//  Sparkle-backed updater integration for Jin.
//

import AppKit
import Foundation
import Sparkle

@MainActor
final class SparkleUpdateManager: NSObject, ObservableObject {
    fileprivate static let preReleaseChannel = "beta"

    private let updaterDelegate: SparkleUpdaterDelegate
    private let userDefaults: UserDefaults
    let controller: SPUStandardUpdaterController
    let updater: SPUUpdater

    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var automaticallyChecksForUpdates: Bool = false
    @Published private(set) var allowPreRelease: Bool = false

    private var hasCheckedOnLaunch = false

    init(
        userDefaults: UserDefaults = .standard,
        startingUpdater: Bool = true
    ) {
        let placeholderDelegate = SparkleUpdaterDelegate()
        self.updaterDelegate = placeholderDelegate
        self.userDefaults = userDefaults
        self.controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: placeholderDelegate,
            userDriverDelegate: nil
        )
        self.updater = controller.updater

        super.init()

        placeholderDelegate.owner = self
        setInitialStateFromStoredPreferences()
        refreshPublishedProperties()
    }

    func setInitialStateFromStoredPreferences() {
        let autoCheck = objectBooleanValue(
            AppPreferenceKeys.updateAutoCheckOnLaunch,
            defaultValue: true
        )
        let allowPreRelease = objectBooleanValue(
            AppPreferenceKeys.updateAllowPreRelease,
            defaultValue: false
        )

        setAutomaticallyChecksForUpdates(autoCheck)
        setAllowsPreReleaseUpdates(allowPreRelease)
    }

    func refreshPublishedProperties() {
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    func checkForUpdatesOnLaunchIfNeeded() async {
        guard !hasCheckedOnLaunch else { return }
        hasCheckedOnLaunch = true

        guard automaticallyChecksForUpdates else { return }
        updater.checkForUpdatesInBackground()
        refreshPublishedProperties()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        if updater.automaticallyChecksForUpdates != enabled {
            updater.automaticallyChecksForUpdates = enabled
        }

        userDefaults.set(enabled, forKey: AppPreferenceKeys.updateAutoCheckOnLaunch)
        refreshPublishedProperties()
    }

    func setAllowsPreReleaseUpdates(_ enabled: Bool) {
        allowPreRelease = enabled
        userDefaults.set(enabled, forKey: AppPreferenceKeys.updateAllowPreRelease)
        refreshPublishedProperties()
    }

    func triggerManualCheck() {
        if updater.canCheckForUpdates {
            updater.checkForUpdates()
        }

        refreshPublishedProperties()
    }

    private func objectBooleanValue(_ key: String, defaultValue: Bool) -> Bool {
        guard let stored = userDefaults.object(forKey: key) as? Bool else {
            return defaultValue
        }
        return stored
    }
}

final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    weak var owner: SparkleUpdateManager?

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        guard let owner, owner.allowPreRelease else {
            return []
        }
        return Set([SparkleUpdateManager.preReleaseChannel])
    }
}
