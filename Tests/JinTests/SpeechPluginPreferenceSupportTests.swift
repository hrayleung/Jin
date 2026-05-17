import XCTest
@testable import Jin

final class SpeechPluginPreferenceSupportTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SpeechPluginPreferenceSupportTests-\(UUID().uuidString)"
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

    func testTrimmedAndNormalizedStringValues() {
        XCTAssertEqual(SpeechPluginPreferenceSupport.trimmed("  token\n"), "token")
        XCTAssertEqual(SpeechPluginPreferenceSupport.trimmed(nil), "")
        XCTAssertEqual(SpeechPluginPreferenceSupport.normalized("  en-US "), "en-US")
        XCTAssertNil(SpeechPluginPreferenceSupport.normalized(" \n\t "))
        XCTAssertNil(SpeechPluginPreferenceSupport.normalized(nil))
    }

    func testResolvedBaseURLUsesFallbackForMissingOrBlankStoredValue() throws {
        XCTAssertEqual(
            try SpeechPluginPreferenceSupport.resolvedBaseURL(nil, fallback: "https://api.example.com/v1"),
            URL(string: "https://api.example.com/v1")
        )
        XCTAssertEqual(
            try SpeechPluginPreferenceSupport.resolvedBaseURL(" \n ", fallback: "https://api.example.com/v1"),
            URL(string: "https://api.example.com/v1")
        )
    }

    func testResolvedBaseURLUsesTrimmedStoredValueAndReportsInvalidURL() throws {
        XCTAssertEqual(
            try SpeechPluginPreferenceSupport.resolvedBaseURL(" https://proxy.example.com/audio ", fallback: "https://api.example.com/v1"),
            URL(string: "https://proxy.example.com/audio")
        )

        XCTAssertThrowsError(
            try SpeechPluginPreferenceSupport.resolvedBaseURL("https://[bad", fallback: "https://api.example.com/v1")
        ) { error in
            guard case SpeechExtensionError.invalidBaseURL("https://[bad") = error else {
                return XCTFail("Expected invalidBaseURL, got \(error)")
            }
        }
    }

    func testResolvedTimestampGranularitiesDropsEmptyAndInvalidJSON() {
        XCTAssertNil(SpeechPluginPreferenceSupport.resolvedTimestampGranularities(nil))
        XCTAssertNil(SpeechPluginPreferenceSupport.resolvedTimestampGranularities("[]"))
        XCTAssertNil(SpeechPluginPreferenceSupport.resolvedTimestampGranularities("not-json"))
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.resolvedTimestampGranularities("[\"segment\",\"word\"]"),
            ["segment", "word"]
        )
    }

    func testResolvedSpeechToTextProviderDecodesConfiguredProvider() throws {
        defaults.set(SpeechToTextProvider.groq.rawValue, forKey: AppPreferenceKeys.sttProvider)

        XCTAssertEqual(
            try SpeechPluginPreferenceSupport.resolvedSpeechToTextProvider(defaults: defaults),
            .groq
        )
    }

    func testResolvedSpeechToTextProviderReportsMissingAndInvalidValues() {
        XCTAssertThrowsError(try SpeechPluginPreferenceSupport.resolvedSpeechToTextProvider(defaults: defaults)) { error in
            guard case SpeechExtensionError.speechToTextProviderNotConfigured = error else {
                return XCTFail("Expected speechToTextProviderNotConfigured, got \(error)")
            }
        }

        defaults.set("bad-stt", forKey: AppPreferenceKeys.sttProvider)
        XCTAssertThrowsError(try SpeechPluginPreferenceSupport.resolvedSpeechToTextProvider(defaults: defaults)) { error in
            guard case SpeechExtensionError.invalidSpeechToTextProvider("bad-stt") = error else {
                return XCTFail("Expected invalidSpeechToTextProvider, got \(error)")
            }
        }
    }

    func testResolvedTextToSpeechProviderDecodesConfiguredProvider() throws {
        defaults.set(TextToSpeechProvider.xiaomiMiMo.rawValue, forKey: AppPreferenceKeys.ttsProvider)

        XCTAssertEqual(
            try SpeechPluginPreferenceSupport.resolvedTextToSpeechProvider(defaults: defaults),
            .xiaomiMiMo
        )
    }

    func testResolvedTextToSpeechProviderReportsMissingAndInvalidValues() {
        defaults.set(" ", forKey: AppPreferenceKeys.ttsProvider)
        XCTAssertThrowsError(try SpeechPluginPreferenceSupport.resolvedTextToSpeechProvider(defaults: defaults)) { error in
            guard case SpeechExtensionError.textToSpeechProviderNotConfigured = error else {
                return XCTFail("Expected textToSpeechProviderNotConfigured, got \(error)")
            }
        }

        defaults.set("bad-tts", forKey: AppPreferenceKeys.ttsProvider)
        XCTAssertThrowsError(try SpeechPluginPreferenceSupport.resolvedTextToSpeechProvider(defaults: defaults)) { error in
            guard case SpeechExtensionError.invalidTextToSpeechProvider("bad-tts") = error else {
                return XCTFail("Expected invalidTextToSpeechProvider, got \(error)")
            }
        }
    }

    func testSpeechToTextAPIKeyPreferenceKeys() {
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.speechToTextAPIKeyPreferenceKey(for: .openai),
            AppPreferenceKeys.sttOpenAIAPIKey
        )
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.speechToTextAPIKeyPreferenceKey(for: .groq),
            AppPreferenceKeys.sttGroqAPIKey
        )
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.speechToTextAPIKeyPreferenceKey(for: .mistral),
            AppPreferenceKeys.sttMistralAPIKey
        )
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.speechToTextAPIKeyPreferenceKey(for: .elevenlabs),
            AppPreferenceKeys.sttElevenLabsAPIKey
        )
    }

    func testTextToSpeechAPIKeyPreferenceKeys() {
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.textToSpeechAPIKeyPreferenceKey(for: .elevenlabs),
            AppPreferenceKeys.ttsElevenLabsAPIKey
        )
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.textToSpeechAPIKeyPreferenceKey(for: .openai),
            AppPreferenceKeys.ttsOpenAIAPIKey
        )
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.textToSpeechAPIKeyPreferenceKey(for: .groq),
            AppPreferenceKeys.ttsGroqAPIKey
        )
        XCTAssertEqual(
            SpeechPluginPreferenceSupport.textToSpeechAPIKeyPreferenceKey(for: .xiaomiMiMo),
            AppPreferenceKeys.ttsMiMoAPIKey
        )
    }
}
