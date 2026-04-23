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

    func testTextToSpeechConfigNormalizesLegacyTTSKitModelAndPlaybackSettings() throws {
        defaults.set(TextToSpeechProvider.whisperKit.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set("qwen3-tts-0.6b", forKey: AppPreferenceKeys.ttsTTSKitModel)
        defaults.set("serena", forKey: AppPreferenceKeys.ttsTTSKitVoice)
        defaults.set("chinese", forKey: AppPreferenceKeys.ttsTTSKitLanguage)
        defaults.set("generate_first", forKey: AppPreferenceKeys.ttsTTSKitPlaybackMode)
        defaults.set("calm documentary narration", forKey: AppPreferenceKeys.ttsTTSKitStyleInstruction)

        let config = try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)
        guard case .ttsKit(let ttsKit) = config else {
            return XCTFail("Expected TTSKit config, got \(config)")
        }

        XCTAssertEqual(ttsKit.model, "0.6b")
        XCTAssertEqual(ttsKit.voice, "serena")
        XCTAssertEqual(ttsKit.language, "chinese")
        XCTAssertEqual(ttsKit.playbackMode, .generateFirst)
        XCTAssertNil(ttsKit.styleInstruction)
    }

    func testTextToSpeechConfigAllowsStyleInstructionForTTSKit17B() throws {
        defaults.set(TextToSpeechProvider.whisperKit.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set("1.7b", forKey: AppPreferenceKeys.ttsTTSKitModel)
        defaults.set("warm audiobook", forKey: AppPreferenceKeys.ttsTTSKitStyleInstruction)

        let config = try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)
        guard case .ttsKit(let ttsKit) = config else {
            return XCTFail("Expected TTSKit config, got \(config)")
        }

        XCTAssertEqual(ttsKit.styleInstruction, "warm audiobook")
        XCTAssertEqual(ttsKit.playbackMode, .auto)
    }

    func testSpeechToTextConfigDisablesElevenLabsNoVerbatimForScribeV1() throws {
        defaults.set(SpeechToTextProvider.elevenlabs.rawValue, forKey: AppPreferenceKeys.sttProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.sttElevenLabsAPIKey)
        defaults.set("scribe_v1", forKey: AppPreferenceKeys.sttElevenLabsModel)
        defaults.set(true, forKey: AppPreferenceKeys.sttElevenLabsNoVerbatim)

        let config = try SpeechPluginConfigFactory.speechToTextConfig(defaults: defaults)
        guard case .elevenlabs(let elevenLabs) = config else {
            return XCTFail("Expected ElevenLabs config, got \(config)")
        }

        XCTAssertEqual(elevenLabs.modelId, "scribe_v1")
        XCTAssertNil(elevenLabs.noVerbatim)
    }

    func testSpeechToTextConfigPreservesElevenLabsNoVerbatimForScribeV2() throws {
        defaults.set(SpeechToTextProvider.elevenlabs.rawValue, forKey: AppPreferenceKeys.sttProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.sttElevenLabsAPIKey)
        defaults.set("scribe_v2", forKey: AppPreferenceKeys.sttElevenLabsModel)
        defaults.set(true, forKey: AppPreferenceKeys.sttElevenLabsNoVerbatim)

        let config = try SpeechPluginConfigFactory.speechToTextConfig(defaults: defaults)
        guard case .elevenlabs(let elevenLabs) = config else {
            return XCTFail("Expected ElevenLabs config, got \(config)")
        }

        XCTAssertEqual(elevenLabs.modelId, "scribe_v2")
        XCTAssertEqual(elevenLabs.noVerbatim, true)
    }
}
