import XCTest
@testable import Jin

final class AppPreferencesSnapshotStoreTests: XCTestCase {
    func testCurrentDomainOverridesLegacyJinDomain() {
        let suiteName = "AppPreferencesSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let currentDomain = "AppPreferencesSnapshotStoreTests.current.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.removePersistentDomain(forName: "Jin")
            defaults.removePersistentDomain(forName: currentDomain)
        }

        defaults.setPersistentDomain(["sharedKey": "legacy"], forName: "Jin")
        defaults.setPersistentDomain(["sharedKey": "current"], forName: currentDomain)

        let merged = AppPreferencesSnapshotStore.mergedPreferenceDictionary(
            defaults: defaults,
            currentDomainOverride: currentDomain
        )
        XCTAssertEqual(merged["sharedKey"] as? String, "current")
    }

    func testCanonicalReleaseDomainStillWinsOverLegacyJinDomain() {
        let suiteName = "AppPreferencesSnapshotStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: "com.jin.app")
            defaults.removePersistentDomain(forName: "Jin")
        }

        defaults.setPersistentDomain(["sharedKey": "release"], forName: "com.jin.app")
        defaults.setPersistentDomain(["sharedKey": "legacy"], forName: "Jin")

        let merged = AppPreferencesSnapshotStore.mergedPreferenceDictionary(
            defaults: defaults,
            currentDomainOverride: "com.jin.app"
        )
        XCTAssertEqual(merged["sharedKey"] as? String, "release")
    }
}
