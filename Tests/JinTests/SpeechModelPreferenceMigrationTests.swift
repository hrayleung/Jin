import Foundation
import XCTest
@testable import Jin

final class SpeechModelPreferenceMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SpeechModelPreferenceMigrationTests-\(UUID().uuidString)"
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

    func testMigratesRetiredTextToSpeechSelections() {
        defaults.set("tts-1-hd", forKey: AppPreferenceKeys.ttsOpenAIModel)
        defaults.set("ballad", forKey: AppPreferenceKeys.ttsOpenAIVoice)
        defaults.set("openai/gpt-4o-mini-tts-2025-12-15", forKey: AppPreferenceKeys.ttsOpenRouterModel)
        defaults.set("alloy", forKey: AppPreferenceKeys.ttsOpenRouterVoice)
        defaults.set("mimo-v2-tts", forKey: AppPreferenceKeys.ttsMiMoModel)
        defaults.set("default_zh", forKey: AppPreferenceKeys.ttsMiMoVoice)
        defaults.set("mp3", forKey: AppPreferenceKeys.ttsMiMoResponseFormat)
        defaults.set("eleven_turbo_v2_5", forKey: AppPreferenceKeys.ttsElevenLabsModelID)
        defaults.set(0.42, forKey: AppPreferenceKeys.ttsElevenLabsStability)

        SpeechModelPreferenceMigration.run(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppPreferenceKeys.ttsOpenAIModel),
            SpeechProviderModelCatalog.defaultOpenAITextToSpeechModelID
        )
        // `ballad` is valid on gpt-4o-mini-tts, so it survives the model bump.
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsOpenAIVoice), "ballad")

        XCTAssertEqual(
            defaults.string(forKey: AppPreferenceKeys.ttsOpenRouterModel),
            SpeechProviderModelCatalog.defaultOpenRouterTextToSpeechModelID
        )
        // OpenRouter has no OpenAI TTS model left, so `alloy` is not a valid voice anywhere.
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsOpenRouterVoice), "Zephyr")

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsMiMoModel), MiMoModelIDs.ttsV25)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsMiMoVoice), "mimo_default")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsMiMoResponseFormat), "wav")

        XCTAssertEqual(
            defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsModelID),
            SpeechProviderModelCatalog.defaultElevenLabsTextToSpeechModelID
        )
        // v3 accepts only 0.0 / 0.5 / 1.0.
        XCTAssertEqual(defaults.double(forKey: AppPreferenceKeys.ttsElevenLabsStability), 0.5)
    }

    func testMigratesSupersededSpeechToTextSelections() {
        defaults.set("gpt-4o-mini-transcribe", forKey: AppPreferenceKeys.sttOpenAIModel)
        defaults.set("verbose_json", forKey: AppPreferenceKeys.sttOpenAIResponseFormat)
        defaults.set("[\"word\"]", forKey: AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON)
        defaults.set(true, forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish)
        defaults.set("openai/whisper-1", forKey: AppPreferenceKeys.sttOpenRouterModel)
        defaults.set("voxtral-mini-latest", forKey: AppPreferenceKeys.sttMistralModel)
        defaults.set("scribe_v1", forKey: AppPreferenceKeys.sttElevenLabsModel)
        defaults.set("srt", forKey: AppPreferenceKeys.sttGroqResponseFormat)

        SpeechModelPreferenceMigration.run(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttOpenAIModel), "gpt-transcribe")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttOpenAIResponseFormat), "json")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttOpenAITimestampGranularitiesJSON), "[]")
        XCTAssertFalse(defaults.bool(forKey: AppPreferenceKeys.sttOpenAITranslateToEnglish))
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttOpenRouterModel), "openai/gpt-transcribe")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttMistralModel), "voxtral-mini-2602")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttElevenLabsModel), "scribe_v2")
        // Groq never accepted srt on the transcription endpoint.
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttGroqResponseFormat), "json")
    }

    /// Diarization is a deliberate capability choice, not a stale default.
    func testDiarizeModelIsNotMigrated() {
        defaults.set("gpt-4o-transcribe-diarize", forKey: AppPreferenceKeys.sttOpenAIModel)
        defaults.set("diarized_json", forKey: AppPreferenceKeys.sttOpenAIResponseFormat)

        SpeechModelPreferenceMigration.run(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttOpenAIModel), "gpt-4o-transcribe-diarize")
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.sttOpenAIResponseFormat), "diarized_json")
    }

    /// Without the version gate a deliberate post-upgrade choice would be rewritten on every
    /// launch.
    func testMigrationRunsOnlyOnce() {
        defaults.set("eleven_multilingual_v2", forKey: AppPreferenceKeys.ttsElevenLabsModelID)
        SpeechModelPreferenceMigration.run(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsModelID), "eleven_v3")

        // The user deliberately picks the low-latency model afterwards.
        defaults.set("eleven_flash_v2_5", forKey: AppPreferenceKeys.ttsElevenLabsModelID)
        SpeechModelPreferenceMigration.run(defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: AppPreferenceKeys.ttsElevenLabsModelID), "eleven_flash_v2_5")
        XCTAssertEqual(
            defaults.integer(forKey: AppPreferenceKeys.speechModelMigrationVersion),
            SpeechModelPreferenceMigration.currentVersion
        )
    }

    func testMigrationLeavesUntouchedInstallsAtDefaults() {
        SpeechModelPreferenceMigration.run(defaults: defaults)

        // Nothing was stored, so nothing should be written beyond the version marker.
        XCTAssertNil(defaults.string(forKey: AppPreferenceKeys.ttsOpenAIModel))
        XCTAssertNil(defaults.string(forKey: AppPreferenceKeys.sttElevenLabsModel))
        XCTAssertEqual(
            defaults.integer(forKey: AppPreferenceKeys.speechModelMigrationVersion),
            SpeechModelPreferenceMigration.currentVersion
        )
    }
}
