import XCTest
@testable import Jin

final class TextToSpeechTTSKitSampleBufferTests: XCTestCase {
    func testAppendRejectsEmptySamplesAndInvalidSampleRate() {
        var buffer = TextToSpeechTTSKitSampleBuffer()

        XCTAssertNil(
            buffer.append(
                [],
                sampleRate: 24_000,
                secondsPerPeak: TextToSpeechSynthesisExecutor.waveformSecondsPerPeak
            )
        )
        XCTAssertNil(
            buffer.append(
                [0.1, 0.2],
                sampleRate: 0,
                secondsPerPeak: TextToSpeechSynthesisExecutor.waveformSecondsPerPeak
            )
        )
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.drainQueuedClip())
    }

    func testAppendTracksDurationWaveformAndFlushThresholds() throws {
        var buffer = TextToSpeechTTSKitSampleBuffer()
        let result = try XCTUnwrap(
            buffer.append(
                [0, 0.25, -0.5, 0.75],
                sampleRate: 4,
                secondsPerPeak: 0.5
            )
        )

        XCTAssertEqual(result.duration, 1)
        XCTAssertEqual(result.waveformPeaks.count, 2)
        XCTAssertFalse(buffer.isEmpty)
        XCTAssertFalse(
            buffer.shouldFlush(
                force: false,
                shouldPrimePlayback: false,
                initialBatchDuration: 0.1,
                clipBatchDuration: 2
            )
        )
        XCTAssertTrue(
            buffer.shouldFlush(
                force: false,
                shouldPrimePlayback: true,
                initialBatchDuration: 1,
                clipBatchDuration: 2
            )
        )
    }

    func testDrainReturnsQueuedClipAndKeepsSampleRateForLaterAppends() throws {
        var buffer = TextToSpeechTTSKitSampleBuffer()
        _ = buffer.append(
            [0, 0.25, -0.25, 0.5],
            sampleRate: 4,
            secondsPerPeak: 0.5
        )

        let firstClip = try XCTUnwrap(buffer.drainQueuedClip())
        XCTAssertEqual(firstClip.duration, 1)
        XCTAssertFalse(firstClip.audioData.isEmpty)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.drainQueuedClip())

        _ = buffer.append(
            [0.5, 0.25],
            sampleRate: 4,
            secondsPerPeak: 0.5
        )
        let secondClip = try XCTUnwrap(buffer.drainQueuedClip())
        XCTAssertEqual(secondClip.duration, 0.5)
    }

    func testResetClearsPendingSamplesAndSampleRate() {
        var buffer = TextToSpeechTTSKitSampleBuffer()
        _ = buffer.append(
            [0.1, 0.2, 0.3],
            sampleRate: 3,
            secondsPerPeak: 1
        )

        buffer.reset()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.drainQueuedClip())
        XCTAssertFalse(
            buffer.shouldFlush(
                force: true,
                shouldPrimePlayback: true,
                initialBatchDuration: 0.1,
                clipBatchDuration: 0.1
            )
        )
    }
}
