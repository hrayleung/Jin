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
}
