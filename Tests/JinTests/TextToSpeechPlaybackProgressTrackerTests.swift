import CoreGraphics
import XCTest
@testable import Jin

final class TextToSpeechPlaybackProgressTrackerTests: XCTestCase {
    func testRecordGeneratedClipTracksDurationAndWaveformAvailability() {
        var tracker = TextToSpeechPlaybackProgressTracker()
        let silentClip = TextToSpeechQueuedClip(
            audioData: Data(),
            duration: 1.25,
            waveformPeaks: []
        )
        let waveformClip = TextToSpeechQueuedClip(
            audioData: Data(),
            duration: 0.75,
            waveformPeaks: [0.2, 0.8]
        )

        XCTAssertFalse(tracker.recordGeneratedClip(silentClip))
        XCTAssertTrue(tracker.recordGeneratedClip(waveformClip))
        XCTAssertEqual(tracker.generatedDuration, 2.0)

        let metrics = tracker.publishedMetrics(currentTime: 1.0)
        XCTAssertEqual(metrics.duration, 2.0)
        XCTAssertEqual(metrics.progress, 0.5)
    }

    func testRecordGeneratedAudioUpdatesWaveformOnlyWhenPeaksExist() {
        var tracker = TextToSpeechPlaybackProgressTracker()

        XCTAssertFalse(tracker.recordGeneratedAudio(duration: 0.5, waveformPeaks: []))
        XCTAssertTrue(tracker.recordGeneratedAudio(duration: 0.5, waveformPeaks: [0.1, 0.6, 0.3]))
        XCTAssertEqual(tracker.generatedDuration, 1.0)

        let displayed = tracker.displayedWaveformPeaks(targetCount: 2)
        XCTAssertEqual(displayed.count, 2)
        guard let maxPeak = displayed.max() else {
            return XCTFail("Expected displayed waveform peaks.")
        }
        XCTAssertEqual(maxPeak, CGFloat(1), accuracy: CGFloat(0.0001))
    }

    func testQueuedPlaybackTimeIncludesPlayedClipsAndActiveClipTime() {
        var tracker = TextToSpeechPlaybackProgressTracker()
        tracker.recordPlayedClip(
            TextToSpeechQueuedClip(
                audioData: Data(),
                duration: 3.0,
                waveformPeaks: []
            )
        )

        XCTAssertEqual(tracker.playedDuration, 3.0)
        XCTAssertEqual(tracker.queuedPlaybackTime(activeClipCurrentTime: nil), 3.0)
        XCTAssertEqual(tracker.queuedPlaybackTime(activeClipCurrentTime: 1.25), 4.25)
        XCTAssertEqual(tracker.queuedPlaybackTime(activeClipCurrentTime: -5), 3.0)
    }

    func testResetClearsPlaybackProgressAndWaveform() {
        var tracker = TextToSpeechPlaybackProgressTracker()
        _ = tracker.recordGeneratedAudio(duration: 4, waveformPeaks: [0.2, 0.4])
        tracker.recordPlayedClip(
            TextToSpeechQueuedClip(
                audioData: Data(),
                duration: 2,
                waveformPeaks: []
            )
        )

        tracker.reset()

        XCTAssertEqual(tracker.generatedDuration, 0)
        XCTAssertEqual(tracker.playedDuration, 0)
        XCTAssertEqual(tracker.queuedPlaybackTime(activeClipCurrentTime: 1), 1)
        XCTAssertEqual(
            tracker.displayedWaveformPeaks(targetCount: 3),
            [CGFloat(0), CGFloat(0), CGFloat(0)]
        )
    }
}
