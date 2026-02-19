import Foundation
import XCTest
@testable import Jin

final class SpeechPluginConfigFactoryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SpeechPluginConfigFactoryTests-\(UUID().uuidString)"
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

    func testSpeechToTextConfigThrowsWhenProviderRawValueIsInvalid() {
        defaults.set("invalid-provider", forKey: AppPreferenceKeys.sttProvider)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.speechToTextConfig(defaults: defaults)) { error in
            guard case let SpeechExtensionError.invalidSpeechToTextProvider(raw) = error else {
                return XCTFail("Expected invalidSpeechToTextProvider, got \(error)")
            }
            XCTAssertEqual(raw, "invalid-provider")
        }
    }

    func testTextToSpeechConfigThrowsWhenProviderRawValueIsInvalid() {
        defaults.set("invalid-provider", forKey: AppPreferenceKeys.ttsProvider)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)) { error in
            guard case let SpeechExtensionError.invalidTextToSpeechProvider(raw) = error else {
                return XCTFail("Expected invalidTextToSpeechProvider, got \(error)")
            }
            XCTAssertEqual(raw, "invalid-provider")
        }
    }

    func testCurrentSpeechToTextProviderThrowsWhenProviderRawValueIsInvalid() {
        defaults.set("unknown-stt", forKey: AppPreferenceKeys.sttProvider)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.currentSTTProvider(defaults: defaults)) { error in
            guard case let SpeechExtensionError.invalidSpeechToTextProvider(raw) = error else {
                return XCTFail("Expected invalidSpeechToTextProvider, got \(error)")
            }
            XCTAssertEqual(raw, "unknown-stt")
        }
    }

    func testCurrentTextToSpeechProviderThrowsWhenProviderRawValueIsInvalid() {
        defaults.set("unknown-tts", forKey: AppPreferenceKeys.ttsProvider)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.currentTTSProvider(defaults: defaults)) { error in
            guard case let SpeechExtensionError.invalidTextToSpeechProvider(raw) = error else {
                return XCTFail("Expected invalidTextToSpeechProvider, got \(error)")
            }
            XCTAssertEqual(raw, "unknown-tts")
        }
    }

    func testSpeechToTextConfigThrowsWhenProviderIsMissing() {
        defaults.removeObject(forKey: AppPreferenceKeys.sttProvider)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.speechToTextConfig(defaults: defaults)) { error in
            guard case SpeechExtensionError.speechToTextProviderNotConfigured = error else {
                return XCTFail("Expected speechToTextProviderNotConfigured, got \(error)")
            }
        }
    }

    func testTextToSpeechConfigThrowsWhenProviderIsBlank() {
        defaults.set("   ", forKey: AppPreferenceKeys.ttsProvider)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)) { error in
            guard case SpeechExtensionError.textToSpeechProviderNotConfigured = error else {
                return XCTFail("Expected textToSpeechProviderNotConfigured, got \(error)")
            }
        }
    }
}
