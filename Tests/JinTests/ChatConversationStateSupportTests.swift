import XCTest
@testable import Jin

final class ChatConversationStateSupportTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ChatConversationStateSupportTests-\(UUID().uuidString)"
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

    func testResolveExtensionCredentialStatusRequiresTrimmedElevenLabsVoiceID() {
        defaults.set(TextToSpeechProvider.elevenlabs.rawValue, forKey: AppPreferenceKeys.ttsProvider)
        defaults.set(" test-key ", forKey: AppPreferenceKeys.ttsElevenLabsAPIKey)
        defaults.set(" \n\t ", forKey: AppPreferenceKeys.ttsElevenLabsVoiceID)

        var status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertFalse(status.textToSpeechConfigured)

        defaults.set(" voice-id ", forKey: AppPreferenceKeys.ttsElevenLabsVoiceID)
        status = ChatConversationStateSupport.resolveExtensionCredentialStatus(defaults: defaults)
        XCTAssertTrue(status.textToSpeechConfigured)
    }
}
