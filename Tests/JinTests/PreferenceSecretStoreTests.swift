import XCTest
@testable import Jin

final class PreferenceSecretStoreTests: XCTestCase {
    func testLoadSecretMigratesLegacyDefaultsValueIntoKeychain() throws {
        let suiteName = "PreferenceSecretStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let key = "PreferenceSecretStoreTests.migrate.\(UUID().uuidString)"

        defaults.set(" legacy-secret ", forKey: key)

        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? PreferenceSecretStore.deleteSecret(forKey: key, defaults: defaults)
        }

        let loaded = PreferenceSecretStore.loadSecret(forKey: key, defaults: defaults)

        XCTAssertEqual(loaded, "legacy-secret")
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertTrue(PreferenceSecretStore.hasSecret(forKey: key, defaults: defaults))
    }

    func testSaveAndDeleteSecretKeepUserDefaultsClear() throws {
        let suiteName = "PreferenceSecretStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let key = "PreferenceSecretStoreTests.persist.\(UUID().uuidString)"

        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? PreferenceSecretStore.deleteSecret(forKey: key, defaults: defaults)
        }

        try PreferenceSecretStore.saveSecret("saved-secret", forKey: key, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(PreferenceSecretStore.loadSecret(forKey: key, defaults: defaults), "saved-secret")

        try PreferenceSecretStore.deleteSecret(forKey: key, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(PreferenceSecretStore.loadSecret(forKey: key, defaults: defaults), "")
    }
}
