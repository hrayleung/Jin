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

    func testTextToSpeechConfigThrowsWhenElevenLabsVoiceIsBlank() {
        defaults.set(TextToSpeechProvider.elevenlabs.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.ttsElevenLabsAPIKey)
        defaults.set(" \n\t ", forKey: AppPreferenceKeys.ttsElevenLabsVoiceID)

        XCTAssertThrowsError(try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)) { error in
            guard case SpeechExtensionError.missingElevenLabsVoice = error else {
                return XCTFail("Expected missingElevenLabsVoice, got \(error)")
            }
        }
    }

    func testTextToSpeechConfigAllowsWhitespaceWrappedElevenLabsVoice() throws {
        defaults.set(TextToSpeechProvider.elevenlabs.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.ttsElevenLabsAPIKey)
        defaults.set(" voice-id ", forKey: AppPreferenceKeys.ttsElevenLabsVoiceID)

        let config = try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)
        guard case .elevenlabs(let elevenLabs) = config else {
            return XCTFail("Expected ElevenLabs config, got \(config)")
        }

        XCTAssertEqual(elevenLabs.voiceId, " voice-id ")
    }

    /// OpenRouter dropped every OpenAI TTS model, so the retired slug has to route somewhere
    /// that still exists.
    func testTextToSpeechConfigNormalizesRetiredOpenRouterTTSModelAlias() throws {
        defaults.set(TextToSpeechProvider.openRouter.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.ttsOpenRouterAPIKey)
        defaults.set("openai/gpt-4o-mini-tts-2025-12-15", forKey: AppPreferenceKeys.ttsOpenRouterModel)

        let config = try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)
        guard case .openRouter(let openRouter) = config else {
            return XCTFail("Expected OpenRouter config, got \(config)")
        }

        XCTAssertEqual(openRouter.model, SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID)
    }

    /// The convert endpoint's `model_id` enum is scribe_v2 only, so a stored v1 has to be
    /// rewritten rather than sent.
    func testSpeechToTextConfigRewritesRetiredScribeV1() throws {
        defaults.set(SpeechToTextProvider.elevenlabs.rawValue, forKey: AppPreferenceKeys.sttProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.sttElevenLabsAPIKey)
        defaults.set("scribe_v1", forKey: AppPreferenceKeys.sttElevenLabsModel)
        defaults.set(true, forKey: AppPreferenceKeys.sttElevenLabsNoVerbatim)

        let config = try SpeechPluginConfigFactory.speechToTextConfig(defaults: defaults)
        guard case .elevenlabs(let elevenLabs) = config else {
            return XCTFail("Expected ElevenLabs config, got \(config)")
        }

        XCTAssertEqual(elevenLabs.modelId, "scribe_v2")
        XCTAssertEqual(elevenLabs.noVerbatim, true)
    }

    /// The V2.5 series only accepts wav and pcm16.
    func testTextToSpeechConfigClampsRetiredMiMoModelAndFormat() throws {
        defaults.set(TextToSpeechProvider.xiaomiMiMo.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.ttsMiMoAPIKey)
        defaults.set("mimo-v2-tts", forKey: AppPreferenceKeys.ttsMiMoModel)
        defaults.set("mp3", forKey: AppPreferenceKeys.ttsMiMoResponseFormat)
        defaults.set("default_zh", forKey: AppPreferenceKeys.ttsMiMoVoice)

        let config = try SpeechPluginConfigFactory.textToSpeechConfig(defaults: defaults)
        guard case .mimo(let miMo) = config else {
            return XCTFail("Expected MiMo config, got \(config)")
        }

        XCTAssertEqual(miMo.model, MiMoModelIDs.ttsV25)
        XCTAssertEqual(miMo.responseFormat, "wav")
        XCTAssertEqual(miMo.voice, "mimo_default")
    }

    /// `gpt-transcribe` takes `languages[]`, not the singular `language`.
    func testSpeechToTextConfigCarriesGPTTranscribeCapabilities() throws {
        defaults.set(SpeechToTextProvider.openai.rawValue, forKey: AppPreferenceKeys.sttProvider)
        defaults.set("test-key", forKey: AppPreferenceKeys.sttOpenAIAPIKey)
        defaults.set("gpt-transcribe", forKey: AppPreferenceKeys.sttOpenAIModel)
        defaults.set(true, forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish)
        defaults.set("Jin, SwiftData", forKey: AppPreferenceKeys.sttOpenAIKeywords)

        let config = try SpeechPluginConfigFactory.speechToTextConfig(defaults: defaults)
        guard case .openai(let openAI) = config else {
            return XCTFail("Expected OpenAI config, got \(config)")
        }

        XCTAssertEqual(openAI.capabilities.languageParameter, .multiple)
        XCTAssertFalse(openAI.capabilities.supportsTemperature)
        XCTAssertTrue(openAI.capabilities.timestampGranularities.isEmpty)
        // Only whisper-1 still serves /audio/translations.
        XCTAssertFalse(openAI.translateToEnglish)
        XCTAssertEqual(openAI.keywords, ["Jin", "SwiftData"])
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
