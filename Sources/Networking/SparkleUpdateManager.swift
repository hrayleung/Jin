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
    /// Sparkle's own user-defaults key for silent download-and-install. Jin has
    /// no UI for that mode, but Sparkle's stock update alert used to offer it,
    /// so installs can carry a stale `true` here. `SUAllowsAutomaticUpdates` in
    /// Info.plist already neutralises it; this key is cleared so the stored
    /// state matches what the app actually supports.
    fileprivate static let silentAutoInstallDefaultsKey = "SUAutomaticallyUpdate"

    private let updaterDelegate: SparkleUpdaterDelegate
    private let userDriverDelegate: SparkleUserDriverDelegate
    private let userDefaults: UserDefaults
    let controller: SPUStandardUpdaterController
    let updater: SPUUpdater

    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var automaticallyChecksForUpdates: Bool = false
    @Published private(set) var allowPreRelease: Bool = false
    @Published private(set) var sessionInProgress: Bool = false
    @Published private(set) var lastUpdateCheckDate: Date?

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
        launchCheckRetryCount: Int = 120,
        launchCheckRetryDelayNanoseconds: UInt64 = 250_000_000,
        launchCheckReadyEvaluator: (() -> Bool)? = nil,
        launchCheckExecutor: (() -> Void)? = nil,
        launchCheckSleep: (@Sendable (UInt64) async -> Void)? = nil
    ) {
        let placeholderDelegate = SparkleUpdaterDelegate()
        let placeholderUserDriverDelegate = SparkleUserDriverDelegate()
        let standardController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: placeholderDelegate,
            userDriverDelegate: placeholderUserDriverDelegate
        )
        let sparkleUpdater = standardController.updater

        self.updaterDelegate = placeholderDelegate
        self.userDriverDelegate = placeholderUserDriverDelegate
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
        placeholderUserDriverDelegate.owner = self
        setInitialStateFromStoredPreferences()
        refreshPublishedProperties()
    }

    private func setInitialStateFromStoredPreferences() {
        clearStoredSilentAutoInstallPreference()

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

    private func clearStoredSilentAutoInstallPreference() {
        guard userDefaults.object(forKey: Self.silentAutoInstallDefaultsKey) != nil else { return }
        userDefaults.removeObject(forKey: Self.silentAutoInstallDefaultsKey)
    }

    func refreshPublishedProperties() {
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        sessionInProgress = updater.sessionInProgress
        lastUpdateCheckDate = updater.lastUpdateCheckDate
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

        // Budget exhausted while Sparkle stayed busy. Deliberately leave
        // `hasCheckedOnLaunch` unset: marking it here used to burn the launch
        // check outright, so a slow-to-settle updater meant no check at all
        // until the user opened Settings and asked for one by hand.
        refreshPublishedProperties()
    }

    /// Brings an already-found scheduled update alert to the front.
    ///
    /// Sparkle only shows a scheduled update immediately when the alert is ready
    /// within three seconds of `startUpdater` (`appNearUpdaterInitialization` in
    /// `SPUStandardUserDriver`). Jin's launch check never lands inside that
    /// window — the model container loads first, then the readiness poll, then
    /// the feed fetch — so Sparkle parks the alert on the next
    /// `NSApplicationDidBecomeActive` and the user only sees it after leaving
    /// the app and coming back.
    ///
    /// `checkForUpdates()` short-circuits to `showUpdateInFocus` while a driver
    /// is already showing an update, so this refetches nothing and can never
    /// surface the "You're up to date" dialog.
    fileprivate func presentPendingUpdateInFocus() {
        updater.checkForUpdates()
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

@MainActor
final class SparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    weak var owner: SparkleUpdateManager?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Sparkle already does the right thing when it plans to show the alert
        // in focus. Take over the other case, where it would instead wait for
        // the app to be re-activated.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        owner?.presentPendingUpdateInFocus()
    }
}
