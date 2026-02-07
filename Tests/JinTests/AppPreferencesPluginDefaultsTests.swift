import Foundation
import XCTest
@testable import Jin

final class AppPreferencesPluginDefaultsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppPreferencesPluginDefaultsTests-\(UUID().uuidString)"
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

    func testChatNamingPluginDefaultsToDisabled() {
        XCTAssertFalse(AppPreferences.isPluginEnabled("chat_naming", defaults: defaults))
    }

    func testExistingPluginsRemainEnabledByDefault() {
        XCTAssertTrue(AppPreferences.isPluginEnabled("text_to_speech", defaults: defaults))
        XCTAssertTrue(AppPreferences.isPluginEnabled("speech_to_text", defaults: defaults))
        XCTAssertTrue(AppPreferences.isPluginEnabled("mistral_ocr", defaults: defaults))
        XCTAssertTrue(AppPreferences.isPluginEnabled("deepseek_ocr", defaults: defaults))
    }
}
