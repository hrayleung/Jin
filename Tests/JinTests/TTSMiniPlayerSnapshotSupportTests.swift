import CoreGraphics
import XCTest
@testable import Jin

final class TTSMiniPlayerSnapshotSupportTests: XCTestCase {
    private let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!

    func testFormattedTimeClampsNegativeValuesAndUsesMinuteFormat() {
        XCTAssertEqual(TTSMiniPlayerSnapshotSupport.formattedTime(-4), "00:00")
        XCTAssertEqual(TTSMiniPlayerSnapshotSupport.formattedTime(61.9), "01:01")
    }

    func testFormattedTimeUsesHourFormatWhenNeeded() {
        XCTAssertEqual(TTSMiniPlayerSnapshotSupport.formattedTime(3_661), "1:01:01")
    }

    func testActiveMessageIDExtractsGeneratingPlayingAndPausedIDs() {
        XCTAssertEqual(
            TTSMiniPlayerSnapshotSupport.activeMessageID(for: .generating(messageID: messageID)),
            messageID
        )
        XCTAssertEqual(
            TTSMiniPlayerSnapshotSupport.activeMessageID(for: .playing(messageID: messageID)),
            messageID
        )
        XCTAssertEqual(
            TTSMiniPlayerSnapshotSupport.activeMessageID(for: .paused(messageID: messageID)),
            messageID
        )
        XCTAssertNil(TTSMiniPlayerSnapshotSupport.activeMessageID(for: .idle))
    }

    func testSnapshotBuildsGeneratingStateWithoutWaveform() {
        let snapshot = TTSMiniPlayerSnapshotSupport.snapshot(
            state: .generating(messageID: messageID),
            playbackContext: nil,
            waveformPeaks: [0, 0.0005],
            progress: 0,
            currentTime: 0,
            hasNavigateHandler: false
        )

        XCTAssertEqual(snapshot.title, "Text to Speech")
        XCTAssertEqual(snapshot.timeText, "00:00")
        XCTAssertTrue(snapshot.isGenerating)
        XCTAssertFalse(snapshot.isPlaying)
        XCTAssertFalse(snapshot.isPaused)
        XCTAssertTrue(snapshot.showsPrimarySpinner)
        XCTAssertFalse(snapshot.showsWaveform)
        XCTAssertTrue(snapshot.showsWaveformSpinner)
        XCTAssertFalse(snapshot.canNavigate)
        XCTAssertNil(snapshot.navigateToolTip)
    }

    func testSnapshotBuildsPlayingStateWithNavigation() {
        let context = TextToSpeechPlaybackManager.PlaybackContext(
            conversationID: conversationID,
            conversationTitle: "Daily Notes",
            textPreview: "Hello"
        )

        let snapshot = TTSMiniPlayerSnapshotSupport.snapshot(
            state: .playing(messageID: messageID),
            playbackContext: context,
            waveformPeaks: [0, 0.2, 0.5],
            progress: 0.4,
            currentTime: 125,
            hasNavigateHandler: true
        )

        XCTAssertEqual(snapshot.title, "Daily Notes")
        XCTAssertEqual(snapshot.timeText, "02:05")
        XCTAssertEqual(snapshot.waveformPeaks, [0, 0.2, 0.5])
        XCTAssertEqual(snapshot.progress, 0.4)
        XCTAssertFalse(snapshot.isGenerating)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertFalse(snapshot.isPaused)
        XCTAssertFalse(snapshot.showsPrimarySpinner)
        XCTAssertTrue(snapshot.showsWaveform)
        XCTAssertFalse(snapshot.showsWaveformSpinner)
        XCTAssertTrue(snapshot.canNavigate)
        XCTAssertEqual(snapshot.navigateToolTip, "Jump to Daily Notes")
    }

    func testSnapshotRequiresBothContextAndHandlerToNavigate() {
        let context = TextToSpeechPlaybackManager.PlaybackContext(
            conversationID: conversationID,
            conversationTitle: "Daily Notes",
            textPreview: "Hello"
        )

        let withContextOnly = TTSMiniPlayerSnapshotSupport.snapshot(
            state: .paused(messageID: messageID),
            playbackContext: context,
            waveformPeaks: [0.1],
            progress: 0.7,
            currentTime: 5,
            hasNavigateHandler: false
        )
        let withHandlerOnly = TTSMiniPlayerSnapshotSupport.snapshot(
            state: .paused(messageID: messageID),
            playbackContext: nil,
            waveformPeaks: [0.1],
            progress: 0.7,
            currentTime: 5,
            hasNavigateHandler: true
        )

        XCTAssertFalse(withContextOnly.canNavigate)
        XCTAssertFalse(withHandlerOnly.canNavigate)
    }
}
