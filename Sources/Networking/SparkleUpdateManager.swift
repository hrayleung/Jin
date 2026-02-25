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
    private var isCheckingOnLaunch = false
    private let launchCheckRetryCount: Int
    private let launchCheckRetryDelayNanoseconds: UInt64
    private let launchCheckReadyEvaluator: () -> Bool
    private let launchCheckExecutor: () -> Void
    private let launchCheckSleep: @Sendable (UInt64) async -> Void

    init(
        userDefaults: UserDefaults = .standard,
        startingUpdater: Bool = true,
        launchCheckRetryCount: Int = 20,
        launchCheckRetryDelayNanoseconds: UInt64 = 250_000_000,
        launchCheckReadyEvaluator: (() -> Bool)? = nil,
        launchCheckExecutor: (() -> Void)? = nil,
        launchCheckSleep: (@Sendable (UInt64) async -> Void)? = nil
    ) {
        let placeholderDelegate = SparkleUpdaterDelegate()
        let standardController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: placeholderDelegate,
            userDriverDelegate: nil
        )
        let sparkleUpdater = standardController.updater

        self.updaterDelegate = placeholderDelegate
        self.userDefaults = userDefaults
        self.controller = standardController
        self.updater = sparkleUpdater
        self.launchCheckRetryCount = max(0, launchCheckRetryCount)
        self.launchCheckRetryDelayNanoseconds = launchCheckRetryDelayNanoseconds
        self.launchCheckReadyEvaluator = launchCheckReadyEvaluator ?? {
            sparkleUpdater.canCheckForUpdates && !sparkleUpdater.sessionInProgress
        }
        self.launchCheckExecutor = launchCheckExecutor ?? {
            sparkleUpdater.checkForUpdatesInBackground()
        }
        self.launchCheckSleep = launchCheckSleep ?? { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }

        super.init()

        placeholderDelegate.owner = self
        setInitialStateFromStoredPreferences()
        refreshPublishedProperties()
    }

    private func setInitialStateFromStoredPreferences() {
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
        guard !hasCheckedOnLaunch, !isCheckingOnLaunch else { return }
        isCheckingOnLaunch = true
        defer { isCheckingOnLaunch = false }

        refreshPublishedProperties()

        guard automaticallyChecksForUpdates else {
            hasCheckedOnLaunch = true
            return
        }

        for attempt in 0...launchCheckRetryCount {
            refreshPublishedProperties()
            if launchCheckReadyEvaluator() {
                launchCheckExecutor()
                hasCheckedOnLaunch = true
                refreshPublishedProperties()
                return
            }

            guard attempt < launchCheckRetryCount else { break }
            await launchCheckSleep(launchCheckRetryDelayNanoseconds)
        }

        // Sparkle may still be finishing its own cycle; avoid retrying this launch forever.
        hasCheckedOnLaunch = true
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

@MainActor
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    weak var owner: SparkleUpdateManager?

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        guard let owner, owner.allowPreRelease else {
            return []
        }
        return Set([SparkleUpdateManager.preReleaseChannel])
    }
}
