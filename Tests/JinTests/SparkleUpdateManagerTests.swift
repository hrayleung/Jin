import XCTest
@testable import Jin

@MainActor
final class SparkleUpdateManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SparkleUpdateManagerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitialStateUsesStoredPreferences() {
        defaults.set(false, forKey: AppPreferenceKeys.updateAutoCheckOnLaunch)
        defaults.set(true, forKey: AppPreferenceKeys.updateAllowPreRelease)

        let manager = SparkleUpdateManager(userDefaults: defaults, startingUpdater: false)

        XCTAssertFalse(manager.automaticallyChecksForUpdates)
        XCTAssertTrue(manager.allowPreRelease)
    }

    func testInitialStateFallsBackToDefaultPreferences() {
        defaults.removeObject(forKey: AppPreferenceKeys.updateAutoCheckOnLaunch)
        defaults.removeObject(forKey: AppPreferenceKeys.updateAllowPreRelease)

        let manager = SparkleUpdateManager(userDefaults: defaults, startingUpdater: false)

        XCTAssertTrue(manager.automaticallyChecksForUpdates)
        XCTAssertFalse(manager.allowPreRelease)
    }

    func testPreferenceMutationsSyncBackToStorage() {
        let manager = SparkleUpdateManager(userDefaults: defaults, startingUpdater: false)

        manager.setAutomaticallyChecksForUpdates(false)
        manager.setAllowsPreReleaseUpdates(true)

        XCTAssertEqual(defaults.object(forKey: AppPreferenceKeys.updateAutoCheckOnLaunch) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKeys.updateAllowPreRelease) as? Bool, true)
        XCTAssertFalse(manager.automaticallyChecksForUpdates)
        XCTAssertTrue(manager.allowPreRelease)
    }

    func testAllowedChannelsUsesBetaOnlyWhenPreReleaseEnabled() {
        let manager = SparkleUpdateManager(userDefaults: defaults, startingUpdater: false)
        let delegate = SparkleUpdaterDelegate()
        delegate.owner = manager

        XCTAssertEqual(delegate.allowedChannels(for: manager.updater), [])

        manager.setAllowsPreReleaseUpdates(true)

        XCTAssertEqual(delegate.allowedChannels(for: manager.updater), ["beta"])
    }

    func testLaunchCheckRetriesUntilUpdaterIsReadyAndRunsOnce() async {
        var readinessChecks = [false, false, true]
        var backgroundCheckCount = 0

        let manager = SparkleUpdateManager(
            userDefaults: defaults,
            startingUpdater: false,
            launchCheckRetryCount: 5,
            launchCheckRetryDelayNanoseconds: 0,
            launchCheckReadyEvaluator: {
                guard !readinessChecks.isEmpty else { return true }
                return readinessChecks.removeFirst()
            },
            launchCheckExecutor: {
                backgroundCheckCount += 1
            },
            launchCheckSleep: { _ in }
        )

        await manager.checkForUpdatesOnLaunchIfNeeded()
        await manager.checkForUpdatesOnLaunchIfNeeded()

        XCTAssertEqual(backgroundCheckCount, 1)
    }

    func testLaunchCheckConcurrentInvocationIsIgnoredWhileFirstCallInProgress() async {
        let firstAttemptReached = expectation(description: "First launch-check attempt reached")
        var readinessEvaluationCount = 0
        var backgroundCheckCount = 0

        let manager = SparkleUpdateManager(
            userDefaults: defaults,
            startingUpdater: false,
            launchCheckRetryCount: 3,
            launchCheckRetryDelayNanoseconds: 200_000_000,
            launchCheckReadyEvaluator: {
                readinessEvaluationCount += 1
                if readinessEvaluationCount == 1 {
                    firstAttemptReached.fulfill()
                    return false
                }
                return true
            },
            launchCheckExecutor: {
                backgroundCheckCount += 1
            },
            launchCheckSleep: { _ in
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        )

        let firstTask = Task {
            await manager.checkForUpdatesOnLaunchIfNeeded()
        }

        await fulfillment(of: [firstAttemptReached], timeout: 1.0)

        let secondTask = Task {
            await manager.checkForUpdatesOnLaunchIfNeeded()
        }

        await firstTask.value
        await secondTask.value

        XCTAssertEqual(readinessEvaluationCount, 2)
        XCTAssertEqual(backgroundCheckCount, 1)
    }

    func testLaunchCheckDoesNotRunWhenAutomaticChecksDisabled() async {
        defaults.set(false, forKey: AppPreferenceKeys.updateAutoCheckOnLaunch)
        var backgroundCheckCount = 0

        let manager = SparkleUpdateManager(
            userDefaults: defaults,
            startingUpdater: false,
            launchCheckRetryCount: 2,
            launchCheckRetryDelayNanoseconds: 0,
            launchCheckReadyEvaluator: {
                XCTFail("Launch readiness should not be evaluated when automatic checks are disabled.")
                return true
            },
            launchCheckExecutor: {
                backgroundCheckCount += 1
            },
            launchCheckSleep: { _ in }
        )

        await manager.checkForUpdatesOnLaunchIfNeeded()
        await manager.checkForUpdatesOnLaunchIfNeeded()

        XCTAssertEqual(backgroundCheckCount, 0)
    }

    func testLaunchCheckStopsRetryingAfterTimeoutAndDoesNotRepeat() async {
        var readinessEvaluationCount = 0
        var backgroundCheckCount = 0

        let manager = SparkleUpdateManager(
            userDefaults: defaults,
            startingUpdater: false,
            launchCheckRetryCount: 2,
            launchCheckRetryDelayNanoseconds: 0,
            launchCheckReadyEvaluator: {
                readinessEvaluationCount += 1
                return false
            },
            launchCheckExecutor: {
                backgroundCheckCount += 1
            },
            launchCheckSleep: { _ in }
        )

        await manager.checkForUpdatesOnLaunchIfNeeded()
        await manager.checkForUpdatesOnLaunchIfNeeded()

        XCTAssertEqual(readinessEvaluationCount, 3)
        XCTAssertEqual(backgroundCheckCount, 0)
    }
}
