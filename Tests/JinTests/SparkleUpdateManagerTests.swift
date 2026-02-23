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
}
