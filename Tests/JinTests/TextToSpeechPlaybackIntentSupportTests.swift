import XCTest
@testable import Jin

final class TextToSpeechPlaybackIntentSupportTests: XCTestCase {
    private let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let otherMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testToggleIntentPausesQueuedPlaybackForCurrentPlayingMessage() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .playing(messageID: messageID),
                messageID: messageID,
                text: "hello",
                usesNativeStreamingPlayback: false
            ),
            .pauseCurrent
        )
    }

    func testToggleIntentStopsNativePlaybackForCurrentPlayingMessage() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .playing(messageID: messageID),
                messageID: messageID,
                text: "hello",
                usesNativeStreamingPlayback: true
            ),
            .stopCurrent
        )
    }

    func testToggleIntentResumesCurrentPausedMessage() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .paused(messageID: messageID),
                messageID: messageID,
                text: "hello",
                usesNativeStreamingPlayback: false
            ),
            .resumeCurrent
        )
    }

    func testToggleIntentStopsCurrentGeneratingMessage() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .generating(messageID: messageID),
                messageID: messageID,
                text: "hello",
                usesNativeStreamingPlayback: false
            ),
            .stopCurrent
        )
    }

    func testToggleIntentStartsNewPlaybackWithTrimmedText() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .idle,
                messageID: messageID,
                text: "  hello\n",
                usesNativeStreamingPlayback: false
            ),
            .stopCurrentThenStart(trimmedText: "hello")
        )
    }

    func testToggleIntentStopsPreviousPlaybackBeforeStartingAnotherMessage() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .playing(messageID: otherMessageID),
                messageID: messageID,
                text: "hello",
                usesNativeStreamingPlayback: false
            ),
            .stopCurrentThenStart(trimmedText: "hello")
        )
    }

    func testToggleIntentStopsPreviousPlaybackAndIgnoresBlankText() {
        XCTAssertEqual(
            TextToSpeechPlaybackIntentSupport.toggleIntent(
                state: .playing(messageID: otherMessageID),
                messageID: messageID,
                text: " \n\t ",
                usesNativeStreamingPlayback: false
            ),
            .stopCurrentAndIgnoreEmptyInput
        )
    }

    func testStatePredicatesMatchCurrentMessageOnly() {
        XCTAssertTrue(TextToSpeechPlaybackIntentSupport.isGenerating(.generating(messageID: messageID), messageID: messageID))
        XCTAssertTrue(TextToSpeechPlaybackIntentSupport.isPlaying(.playing(messageID: messageID), messageID: messageID))
        XCTAssertTrue(TextToSpeechPlaybackIntentSupport.isPaused(.paused(messageID: messageID), messageID: messageID))
        XCTAssertTrue(TextToSpeechPlaybackIntentSupport.isActive(.playing(messageID: messageID), messageID: messageID))

        XCTAssertFalse(TextToSpeechPlaybackIntentSupport.isGenerating(.generating(messageID: otherMessageID), messageID: messageID))
        XCTAssertFalse(TextToSpeechPlaybackIntentSupport.isPlaying(.playing(messageID: otherMessageID), messageID: messageID))
        XCTAssertFalse(TextToSpeechPlaybackIntentSupport.isPaused(.paused(messageID: otherMessageID), messageID: messageID))
        XCTAssertFalse(TextToSpeechPlaybackIntentSupport.isActive(.idle, messageID: messageID))
    }
}
