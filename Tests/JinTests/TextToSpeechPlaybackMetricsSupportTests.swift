import CoreGraphics
import XCTest
@testable import Jin

final class TextToSpeechPlaybackMetricsSupportTests: XCTestCase {
    func testPublishedMetricsClampNegativeCurrentTime() {
        let metrics = TextToSpeechPlaybackMetricsSupport.publishedMetrics(
            currentTime: -3,
            generatedDuration: 10
        )

        XCTAssertEqual(metrics.currentTime, 0)
        XCTAssertEqual(metrics.duration, 10)
        XCTAssertEqual(metrics.progress, 0)
    }

    func testPublishedMetricsUseGeneratedDurationForProgress() {
        let metrics = TextToSpeechPlaybackMetricsSupport.publishedMetrics(
            currentTime: 2,
            generatedDuration: 8
        )

        XCTAssertEqual(metrics.currentTime, 2)
        XCTAssertEqual(metrics.duration, 8)
        XCTAssertEqual(metrics.progress, 0.25)
    }

    func testPublishedMetricsExtendDurationWhenPlaybackRunsAheadOfGeneratedDuration() {
        let metrics = TextToSpeechPlaybackMetricsSupport.publishedMetrics(
            currentTime: 12,
            generatedDuration: 8
        )

        XCTAssertEqual(metrics.currentTime, 12)
        XCTAssertEqual(metrics.duration, 12)
        XCTAssertEqual(metrics.progress, 1)
    }

    func testDisplayedWaveformPeaksResampleAndNormalizeAccumulatedPeaks() {
        let peaks = TextToSpeechPlaybackMetricsSupport.displayedWaveformPeaks(
            accumulatedPeaks: [0.1, 0.4, 0.2, 0.8],
            targetCount: 2
        )

        XCTAssertEqual(peaks.count, 2)
        guard let maxPeak = peaks.max() else {
            XCTFail("Expected displayed waveform peaks.")
            return
        }
        XCTAssertEqual(maxPeak, CGFloat(1), accuracy: CGFloat(0.0001))
        XCTAssertTrue(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertGreaterThan(peaks.reduce(CGFloat(0), +), 0)
    }

    func testDisplayedWaveformPeaksReturnsZeroFilledOutputForEmptyInput() {
        XCTAssertEqual(
            TextToSpeechPlaybackMetricsSupport.displayedWaveformPeaks(
                accumulatedPeaks: [],
                targetCount: 3
            ),
            [CGFloat(0), CGFloat(0), CGFloat(0)]
        )
    }

    func testTTSKitSampleDurationRejectsInvalidValues() {
        XCTAssertNil(TextToSpeechPlaybackMetricsSupport.ttsKitSampleDuration(sampleCount: 0, sampleRate: 24_000))
        XCTAssertNil(TextToSpeechPlaybackMetricsSupport.ttsKitSampleDuration(sampleCount: 24_000, sampleRate: 0))
        XCTAssertEqual(
            TextToSpeechPlaybackMetricsSupport.ttsKitSampleDuration(sampleCount: 12_000, sampleRate: 24_000),
            0.5
        )
    }

    func testShouldFlushTTSKitSamplesUsesInitialBatchThresholdWhenPriming() {
        XCTAssertFalse(
            TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
                sampleCount: 1_000,
                sampleRate: 10_000,
                force: false,
                shouldPrimePlayback: true,
                initialBatchDuration: 0.12,
                clipBatchDuration: 0.9
            )
        )
        XCTAssertTrue(
            TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
                sampleCount: 1_200,
                sampleRate: 10_000,
                force: false,
                shouldPrimePlayback: true,
                initialBatchDuration: 0.12,
                clipBatchDuration: 0.9
            )
        )
    }

    func testShouldFlushTTSKitSamplesUsesClipBatchThresholdAfterPriming() {
        XCTAssertFalse(
            TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
                sampleCount: 8_000,
                sampleRate: 10_000,
                force: false,
                shouldPrimePlayback: false,
                initialBatchDuration: 0.12,
                clipBatchDuration: 0.9
            )
        )
        XCTAssertTrue(
            TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
                sampleCount: 9_000,
                sampleRate: 10_000,
                force: false,
                shouldPrimePlayback: false,
                initialBatchDuration: 0.12,
                clipBatchDuration: 0.9
            )
        )
    }

    func testShouldFlushTTSKitSamplesHonorsForceForValidPendingSamples() {
        XCTAssertTrue(
            TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
                sampleCount: 1,
                sampleRate: 10_000,
                force: true,
                shouldPrimePlayback: false,
                initialBatchDuration: 0.12,
                clipBatchDuration: 0.9
            )
        )
        XCTAssertFalse(
            TextToSpeechPlaybackMetricsSupport.shouldFlushTTSKitSamples(
                sampleCount: 0,
                sampleRate: 10_000,
                force: true,
                shouldPrimePlayback: false,
                initialBatchDuration: 0.12,
                clipBatchDuration: 0.9
            )
        )
    }
}
